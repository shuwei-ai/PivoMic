#include "karaoke/realtime_mixer.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace karaoke {
namespace {

constexpr float kPcmScale = 32768.0F;
constexpr float kCeiling = 0.96605F; // -0.3 dBFS

float FiniteOrZero(float value) noexcept
{
    return std::isfinite(value) ? value : 0.0F;
}

float SoftLimit(float sample) noexcept
{
    sample = FiniteOrZero(sample);
    const float magnitude = std::fabs(sample);
    if (magnitude <= 0.8F) {
        return sample;
    }
    const float limited = 0.8F + 0.2F * (1.0F - std::exp(-(magnitude - 0.8F) * 5.0F));
    const float clamped = std::copysign(std::min(limited, 1.0F), sample);
    return std::max(-kCeiling, std::min(clamped, kCeiling));
}

int16_t QuantizePcm(float sample) noexcept
{
    const float scaled = SoftLimit(sample) * kPcmScale;
    const float bounded = std::max(-32768.0F, std::min(scaled, 32767.0F));
    return static_cast<int16_t>(std::lround(bounded));
}

} // namespace

RealtimeMixer::RealtimeMixer(uint32_t sampleRate, std::size_t maxFrames)
    : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
      maxFrames_(maxFrames),
      audioRoute_(AudioRouteMode::Speaker),
      antiHowlingEnabled_(true),
      aecEnabled_(true),
      spatialReverbEnabled_(true),
      parametricEqEnabled_(true),
      deEsserEnabled_(true),
      vocalDynamicsEnabled_(true),
      pitchCorrectionEnabled_(false),
      pitchCorrectionStrength_(0.0F),
      accompanimentPitchShift_(0.0F),
      aec_(sampleRate_),
      delayEstimator_(sampleRate_),
      antiHowling_(sampleRate_, 3.5F),
      notchFilter_(sampleRate_),
      pitchCorrector_(sampleRate_),
      accompanimentPitchShifter_(sampleRate_),
      vocalDynamics_(sampleRate_),
      deEsser_(sampleRate_),
      parametricEq_(sampleRate_),
      spatialReverb_(sampleRate_),
      limiter_(sampleRate_, 1.5F),
      gainGuard_(sampleRate_),
      musicWorkBuffer_(std::max<std::size_t>(maxFrames * 4, 4096) * 2, 0.0F),
      rawVocalWorkBuffer_(std::max<std::size_t>(maxFrames * 4, 4096), 0.0F),
      dryVocalWorkBuffer_(std::max<std::size_t>(maxFrames * 4, 4096), 0),
      masterRefBuffer_(std::max<std::size_t>(maxFrames * 4, 4096) * 2, 0.0F)
{
    SetReverbPreset(ReverbPreset::Ktv);
}

float RealtimeMixer::ClampGain(float value) noexcept
{
    if (!std::isfinite(value)) {
        return 0.0F;
    }
    return std::max(0.0F, std::min(value, 2.0F));
}

void RealtimeMixer::SetGains(float accompaniment, float vocal, float reverb) noexcept
{
    accompanimentGain_.store(ClampGain(accompaniment), std::memory_order_relaxed);
    vocalGain_.store(ClampGain(vocal), std::memory_order_relaxed);
    reverbGain_.store(ClampGain(reverb), std::memory_order_relaxed);
}

float RealtimeMixer::AccompanimentGain() const noexcept
{
    return accompanimentGain_.load(std::memory_order_relaxed);
}

float RealtimeMixer::VocalGain() const noexcept
{
    return vocalGain_.load(std::memory_order_relaxed);
}

float RealtimeMixer::ReverbGain() const noexcept
{
    return reverbGain_.load(std::memory_order_relaxed);
}

float RealtimeMixer::Peak() const noexcept
{
    return peak_.load(std::memory_order_relaxed);
}

void RealtimeMixer::SetAudioRoute(AudioRouteMode route) noexcept
{
    const AudioRouteMode previous = audioRoute_.load(std::memory_order_relaxed);
    audioRoute_.store(route, std::memory_order_relaxed);
    if (route == AudioRouteMode::Speaker && previous != AudioRouteMode::Speaker) {
        speakerRampFramesRemaining_.store(sampleRate_, std::memory_order_relaxed);
    }
}

AudioRouteMode RealtimeMixer::AudioRoute() const noexcept
{
    return audioRoute_.load(std::memory_order_relaxed);
}

void RealtimeMixer::SetAntiHowlingEnabled(bool enabled) noexcept
{
    antiHowlingEnabled_.store(enabled, std::memory_order_relaxed);
    antiHowling_.SetEnabled(enabled);
    notchFilter_.SetEnabled(enabled);
}

bool RealtimeMixer::IsAntiHowlingEnabled() const noexcept
{
    return antiHowlingEnabled_.load(std::memory_order_relaxed);
}

void RealtimeMixer::SetAecEnabled(bool enabled) noexcept
{
    aecEnabled_.store(enabled, std::memory_order_relaxed);
    aec_.SetEnabled(enabled);
}

bool RealtimeMixer::IsAecEnabled() const noexcept
{
    return aecEnabled_.load(std::memory_order_relaxed);
}

void RealtimeMixer::SetSpatialReverbEnabled(bool enabled) noexcept
{
    spatialReverbEnabled_.store(enabled, std::memory_order_relaxed);
}

bool RealtimeMixer::IsSpatialReverbEnabled() const noexcept
{
    return spatialReverbEnabled_.load(std::memory_order_relaxed);
}

void RealtimeMixer::SetReverbPreset(ReverbPreset preset) noexcept
{
    switch (preset) {
        case ReverbPreset::Ktv:
            spatialReverb_.SetRoomSize(0.78F);
            spatialReverb_.SetDamping(0.28F);
            spatialReverb_.SetWidth(1.0F);
            break;
        case ReverbPreset::Studio:
            spatialReverb_.SetRoomSize(0.48F);
            spatialReverb_.SetDamping(0.55F);
            spatialReverb_.SetWidth(0.75F);
            break;
        case ReverbPreset::Concert:
            spatialReverb_.SetRoomSize(0.88F);
            spatialReverb_.SetDamping(0.18F);
            spatialReverb_.SetWidth(1.0F);
            break;
        case ReverbPreset::Folk:
            spatialReverb_.SetRoomSize(0.62F);
            spatialReverb_.SetDamping(0.38F);
            spatialReverb_.SetWidth(0.85F);
            break;
    }
}

void RealtimeMixer::SetParametricEqEnabled(bool enabled) noexcept
{
    parametricEqEnabled_.store(enabled, std::memory_order_relaxed);
    parametricEq_.SetEnabled(enabled);
}

bool RealtimeMixer::IsParametricEqEnabled() const noexcept
{
    return parametricEqEnabled_.load(std::memory_order_relaxed);
}

void RealtimeMixer::SetDeEsserEnabled(bool enabled) noexcept
{
    deEsserEnabled_.store(enabled, std::memory_order_relaxed);
    deEsser_.SetEnabled(enabled);
}

bool RealtimeMixer::IsDeEsserEnabled() const noexcept
{
    return deEsserEnabled_.load(std::memory_order_relaxed);
}

void RealtimeMixer::SetVocalDynamicsEnabled(bool enabled) noexcept
{
    vocalDynamicsEnabled_.store(enabled, std::memory_order_relaxed);
}

bool RealtimeMixer::IsVocalDynamicsEnabled() const noexcept
{
    return vocalDynamicsEnabled_.load(std::memory_order_relaxed);
}

void RealtimeMixer::SetAccompanimentPitchShift(float semitones) noexcept
{
    accompanimentPitchShift_.store(semitones, std::memory_order_relaxed);
    accompanimentPitchShifter_.SetSemitones(semitones);
}

float RealtimeMixer::AccompanimentPitchShift() const noexcept
{
    return accompanimentPitchShift_.load(std::memory_order_relaxed);
}

void RealtimeMixer::SetPitchCorrection(bool enabled, float strength, uint32_t scaleType, uint32_t rootNote) noexcept
{
    pitchCorrectionEnabled_.store(enabled, std::memory_order_relaxed);
    pitchCorrectionStrength_.store(strength, std::memory_order_relaxed);
    pitchCorrector_.SetEnabled(enabled);
    pitchCorrector_.SetStrength(strength);
    pitchCorrector_.SetScale(static_cast<PitchScaleType>(scaleType), rootNote);
}

bool RealtimeMixer::IsPitchCorrectionEnabled() const noexcept
{
    return pitchCorrectionEnabled_.load(std::memory_order_relaxed);
}

float RealtimeMixer::PitchCorrectionStrength() const noexcept
{
    return pitchCorrectionStrength_.load(std::memory_order_relaxed);
}

void RealtimeMixer::StartRecording() noexcept
{
    recorder_.StartRecording();
}

void RealtimeMixer::StopRecording() noexcept
{
    recorder_.StopRecording();
}

bool RealtimeMixer::IsRecording() const noexcept
{
    return recorder_.IsRecording();
}

std::size_t RealtimeMixer::RecordedFrames() const noexcept
{
    return recorder_.RecordedFrames();
}

int64_t RealtimeMixer::RecordedDurationMs() const noexcept
{
    return recorder_.RecordedDurationMs();
}

bool RealtimeMixer::ExportRecording(const std::string& outputPath, float vocalGain, float musicGain) const noexcept
{
    return recorder_.ExportMasterWav(outputPath, vocalGain, musicGain);
}

float RealtimeMixer::CurrentAecErleDb() const noexcept
{
    return aec_.CurrentErleDb();
}

RealtimeMixer::StageMetrics RealtimeMixer::GetStageMetrics() const noexcept
{
    return lastStageMetrics_;
}

int16_t RealtimeMixer::ToPcm(float sample) noexcept
{
    return QuantizePcm(sample);
}

void RealtimeMixer::Process(const int16_t *musicStereo, const int16_t *vocalMono,
    int16_t *outputStereo, std::size_t frames) noexcept
{
    if (outputStereo == nullptr || frames == 0 || maxFrames_ == 0) {
        return;
    }

    const std::size_t processFrames = std::min(frames, maxFrames_);
    const float accompanimentGain = AccompanimentGain();
    const float vocalGain = VocalGain();
    const float reverbGain = ReverbGain();
    const bool spatialReverb = IsSpatialReverbEnabled();
    const bool eqActive = IsParametricEqEnabled();
    const bool deEsserActive = IsDeEsserEnabled();
    const bool dynamicsActive = IsVocalDynamicsEnabled();
    const AudioRouteMode route = AudioRoute();
    const bool earReturnAllowed = AudioRoutePolicy::IsEarReturnAllowed(route);
    const bool speakerRoute = route == AudioRouteMode::Speaker;
    std::uint32_t rampFrames = speakerRampFramesRemaining_.load(std::memory_order_relaxed);

    // 1. Process Accompaniment Key Transpose (Pitch Shifting)
    for (std::size_t f = 0; f < processFrames; ++f) {
        musicWorkBuffer_[f * 2] = (musicStereo == nullptr) ? 0.0F : musicStereo[f * 2] / kPcmScale;
        musicWorkBuffer_[f * 2 + 1] = (musicStereo == nullptr) ? 0.0F : musicStereo[f * 2 + 1] / kPcmScale;
    }
    accompanimentPitchShifter_.ProcessStereo(musicWorkBuffer_.data(), processFrames);

    for (std::size_t frame = 0; frame < processFrames; ++frame) {
        rawVocalWorkBuffer_[frame] = vocalMono == nullptr ? 0.0F : vocalMono[frame] / kPcmScale;
    }

    float blockPeak = 0.0F;
    float maxRawPeak = 0.0F;
    float maxShiftPeak = 0.0F;
    float maxDynPeak = 0.0F;
    float maxWetPeak = 0.0F;
    float maxVocalSubPeak = 0.0F;
    float maxMusicSubPeak = 0.0F;
    float maxMasterPeak = 0.0F;
    float recordedEffectiveVocalGain = 0.0F;

    for (std::size_t frame = 0; frame < processFrames; ++frame) {
        const float rawMicInput = rawVocalWorkBuffer_[frame];
        blockPeak = std::max(blockPeak, std::fabs(rawMicInput));
        maxRawPeak = std::max(maxRawPeak, std::fabs(rawMicInput));

        const float musicLeft = musicWorkBuffer_[frame * 2];
        const float musicRight = musicWorkBuffer_[frame * 2 + 1];

        // Layer 1: Front-end Anti-Howling Dynamic Notch Protection
        float vocal = rawMicInput;
        if (speakerRoute && IsAntiHowlingEnabled()) {
            vocal = notchFilter_.ProcessSample(vocal);
        }
        maxShiftPeak = std::max(maxShiftPeak, std::fabs(vocal));

        // Layer 2: Vocal Dynamics Preamp & Conditioning
        if (dynamicsActive) {
            vocal = vocalDynamics_.ProcessSample(vocal);
        } else {
            vocal = std::tanh(vocal * 4.0F); // Basic clean makeup gain
        }

        // Layer 3: Pitch Correction & Vocal Polish
        vocal = pitchCorrector_.ProcessSample(vocal);
        if (deEsserActive) {
            vocal = deEsser_.ProcessSample(vocal);
        }
        if (eqActive) {
            vocal = parametricEq_.ProcessSample(vocal);
        }
        maxDynPeak = std::max(maxDynPeak, std::fabs(vocal));

        // Capture 100% clean pristine studio dry vocal for dual-track recording sink
        // Recorded vocal is captured BEFORE speaker SSB frequency shifting and speaker gain guard!
        dryVocalWorkBuffer_[frame] = QuantizePcm(vocal);

        // Layer 4: High-density Stereo Spatial Reverb
        float wetLeft = 0.0F;
        float wetRight = 0.0F;
        if (spatialReverb) {
            spatialReverb_.ProcessSample(vocal, wetLeft, wetRight);
        }
        maxWetPeak = std::max(maxWetPeak, std::max(std::fabs(wetLeft), std::fabs(wetRight)));

        // Subbus A: Pure Accompaniment
        const float musicSubL = musicLeft * accompanimentGain;
        const float musicSubR = musicRight * accompanimentGain;
        maxMusicSubPeak = std::max(maxMusicSubPeak, std::max(std::fabs(musicSubL), std::fabs(musicSubR)));

        // Subbus B: Live Processed Vocal & Reverb
        float vocalSubL = 0.0F;
        float vocalSubR = 0.0F;

        if (earReturnAllowed) {
            if (speakerRoute) {
                // 1. Relocate +3.5Hz SSB Frequency Shifter exclusively to Speaker Ear-Return branch
                float speakerVocal = vocal;
                if (IsAntiHowlingEnabled()) {
                    speakerVocal = antiHowling_.ProcessSample(speakerVocal);
                }

                // 2. Intelligent Loop Gain Guard (2~5ms fast-duck on runaway, 1.5s smooth return, zero pumping)
                const float guardFactor = gainGuard_.ProcessSample(speakerVocal);

                // Calibrated safe speaker vocal scale (raised from 0.40F to 0.50F with SSB + FFT notch + Guard protection)
                constexpr float kSpeakerVocalScale = 0.50F;
                constexpr float kSpeakerReverbScale = 0.0F; // Mute digital reverb to built-in speaker to prevent recursive comb howling
                const float rampProgress = 1.0F - static_cast<float>(rampFrames) /
                    static_cast<float>(std::max<std::uint32_t>(sampleRate_, 1));
                const float ramp = 0.70F + 0.30F * rampProgress;

                const float effectiveVocalGain = vocalGain * kSpeakerVocalScale * ramp * guardFactor;
                const float effectiveReverbGain = reverbGain * kSpeakerReverbScale * ramp;
                recordedEffectiveVocalGain = effectiveVocalGain;

                // 3. 2nd-Order Butterworth Bandpass (120Hz HPF + 7.5kHz LPF) to eliminate chassis acoustic resonance
                // 120Hz HPF (Direct Form II Transposed @ 48kHz):
                constexpr float hpfB0 = 0.98895F;
                constexpr float hpfB1 = -1.97790F;
                constexpr float hpfB2 = 0.98895F;
                constexpr float hpfA1 = -1.97779F;
                constexpr float hpfA2 = 0.97801F;

                const float hpfY = hpfB0 * speakerVocal + speakerHpfS1_;
                speakerHpfS1_ = hpfB1 * speakerVocal - hpfA1 * hpfY + speakerHpfS2_;
                speakerHpfS2_ = hpfB2 * speakerVocal - hpfA2 * hpfY;
                float filteredVocal = std::isfinite(hpfY) ? hpfY : speakerVocal;

                // 7.5kHz LPF (Direct Form II Transposed @ 48kHz):
                constexpr float lpfB0 = 0.1311F;
                constexpr float lpfB1 = 0.2622F;
                constexpr float lpfB2 = 0.1311F;
                constexpr float lpfA1 = -0.7478F;
                constexpr float lpfA2 = 0.2722F;

                const float lpfY = lpfB0 * filteredVocal + speakerLpfS1_;
                speakerLpfS1_ = lpfB1 * filteredVocal - lpfA1 * lpfY + speakerLpfS2_;
                speakerLpfS2_ = lpfB2 * filteredVocal - lpfA2 * lpfY;
                filteredVocal = std::isfinite(lpfY) ? lpfY : filteredVocal;

                vocalSubL = filteredVocal * effectiveVocalGain + wetLeft * effectiveReverbGain;
                vocalSubR = filteredVocal * effectiveVocalGain + wetRight * effectiveReverbGain;
                if (rampFrames > 0) --rampFrames;
            } else {
                // Headphone / Headset / Bluetooth Mode: 100% full unattenuated studio vocal + lush spatial reverb
                recordedEffectiveVocalGain = vocalGain;
                vocalSubL = vocal * vocalGain + wetLeft * reverbGain;
                vocalSubR = vocal * vocalGain + wetRight * reverbGain;
            }
            // Soft-knee limiter on vocal sub-bus prevents clipping
            vocalSubL = std::tanh(vocalSubL);
            vocalSubR = std::tanh(vocalSubR);
        }
        maxVocalSubPeak = std::max(maxVocalSubPeak, std::max(std::fabs(vocalSubL), std::fabs(vocalSubR)));

        // Master Summing
        const float masterL = musicSubL + vocalSubL;
        const float masterR = musicSubR + vocalSubR;
        maxMasterPeak = std::max(maxMasterPeak, std::max(std::fabs(masterL), std::fabs(masterR)));

        outputStereo[frame * 2] = QuantizePcm(masterL);
        outputStereo[frame * 2 + 1] = QuantizePcm(masterR);

        // Store to master loopback reference buffer for next block's AEC alignment
        masterRefBuffer_[frame * 2] = masterL;
        masterRefBuffer_[frame * 2 + 1] = masterR;
    }

    lastStageMetrics_ = {
        maxRawPeak,
        maxShiftPeak,
        maxDynPeak,
        maxWetPeak,
        maxVocalSubPeak,
        maxMusicSubPeak,
        maxMasterPeak,
        vocalDynamics_.CurrentGateGain(),
        1.0F,
        recordedEffectiveVocalGain
    };

    if (speakerRoute) {
        speakerRampFramesRemaining_.store(rampFrames, std::memory_order_relaxed);
    }

    // Push synchronous clean dry vocal + accompaniment to dual-track recording sink
    if (recorder_.IsRecording()) {
        recorder_.PushFrame(dryVocalWorkBuffer_.data(), musicStereo, processFrames);
    }

    peak_.store(std::min(blockPeak, 1.0F), std::memory_order_relaxed);
}

void RealtimeMixer::Reset() noexcept
{
    peak_.store(0.0F, std::memory_order_relaxed);
    if (AudioRoute() == AudioRouteMode::Speaker) {
        speakerRampFramesRemaining_.store(sampleRate_, std::memory_order_relaxed);
    }
    std::fill(masterRefBuffer_.begin(), masterRefBuffer_.end(), 0.0F);
    speakerHpfS1_ = 0.0F;
    speakerHpfS2_ = 0.0F;
    speakerLpfS1_ = 0.0F;
    speakerLpfS2_ = 0.0F;
    gainGuard_.Reset();
    aec_.Reset();
    delayEstimator_.Reset();
    antiHowling_.Reset();
    notchFilter_.Reset();
    pitchCorrector_.Reset();
    accompanimentPitchShifter_.Reset();
    vocalDynamics_.Reset();
    deEsser_.Reset();
    parametricEq_.Reset();
    spatialReverb_.Reset();
    limiter_.Reset();
    recorder_.Reset();
}

} // namespace karaoke
