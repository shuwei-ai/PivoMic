#ifndef PIVOMIC_KARAOKE_REALTIME_MIXER_H
#define PIVOMIC_KARAOKE_REALTIME_MIXER_H

#include "accompaniment_pitch_shifter.h"
#include "acoustic_echo_canceller.h"
#include "acoustic_delay_estimator.h"
#include "anti_howling_shifter.h"
#include "audio_route_manager.h"
#include "de_esser.h"
#include "dual_track_recorder.h"
#include "dynamic_notch_filter.h"
#include "lookahead_limiter.h"
#include "parametric_eq.h"
#include "feedback_gain_guard.h"
#include "pitch_corrector.h"
#include "spatial_reverb.h"
#include "vocal_dynamics.h"

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace karaoke {

enum class ReverbPreset : uint32_t {
    Ktv = 0,
    Studio = 1,
    Concert = 2,
    Folk = 3
};

class RealtimeMixer final {
public:
    RealtimeMixer(uint32_t sampleRate, std::size_t maxFrames);

    void SetGains(float accompaniment, float vocal, float reverb) noexcept;
    [[nodiscard]] float AccompanimentGain() const noexcept;
    [[nodiscard]] float VocalGain() const noexcept;
    [[nodiscard]] float ReverbGain() const noexcept;
    [[nodiscard]] float Peak() const noexcept;

    void SetAudioRoute(AudioRouteMode route) noexcept;
    [[nodiscard]] AudioRouteMode AudioRoute() const noexcept;

    void SetAntiHowlingEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsAntiHowlingEnabled() const noexcept;

    void SetAecEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsAecEnabled() const noexcept;

    void SetSpatialReverbEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsSpatialReverbEnabled() const noexcept;

    void SetReverbPreset(ReverbPreset preset) noexcept;

    void SetParametricEqEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsParametricEqEnabled() const noexcept;

    void SetDeEsserEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsDeEsserEnabled() const noexcept;

    void SetVocalDynamicsEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsVocalDynamicsEnabled() const noexcept;

    void SetAccompanimentPitchShift(float semitones) noexcept;
    [[nodiscard]] float AccompanimentPitchShift() const noexcept;

    void SetPitchCorrection(bool enabled, float strength, uint32_t scaleType, uint32_t rootNote) noexcept;
    [[nodiscard]] bool IsPitchCorrectionEnabled() const noexcept;
    [[nodiscard]] float PitchCorrectionStrength() const noexcept;

    void StartRecording() noexcept;
    void StopRecording() noexcept;
    [[nodiscard]] bool IsRecording() const noexcept;
    [[nodiscard]] std::size_t RecordedFrames() const noexcept;
    [[nodiscard]] int64_t RecordedDurationMs() const noexcept;
    [[nodiscard]] bool ExportRecording(const std::string& outputPath, float vocalGain = 1.2F, float musicGain = 0.8F) const noexcept;
    const DualTrackRecorder& Recorder() const noexcept { return recorder_; }

    struct StageMetrics {
        float rawPeak {0.0F};
        float shiftPeak {0.0F};
        float dynPeak {0.0F};
        float wetPeak {0.0F};
        float vocalSubPeak {0.0F};
        float musicSubPeak {0.0F};
        float masterPeak {0.0F};
        float gateGain {1.0F};
        float compGain {1.0F};
        float effectiveVocalGain {0.0F};
    };

    [[nodiscard]] float CurrentAecErleDb() const noexcept;
    [[nodiscard]] StageMetrics GetStageMetrics() const noexcept;

    void Process(const int16_t *musicStereo, const int16_t *vocalMono,
        int16_t *outputStereo, std::size_t frames) noexcept;
    void Reset() noexcept;

private:
    static float ClampGain(float value) noexcept;
    static int16_t ToPcm(float sample) noexcept;

    uint32_t sampleRate_;
    std::size_t maxFrames_;
    std::atomic<float> accompanimentGain_ {1.0F};
    std::atomic<float> vocalGain_ {1.0F};
    std::atomic<float> reverbGain_ {0.0F};
    std::atomic<float> peak_ {0.0F};
    std::atomic<AudioRouteMode> audioRoute_ {AudioRouteMode::Speaker};
    std::atomic<bool> antiHowlingEnabled_ {true};
    std::atomic<bool> aecEnabled_ {true};
    std::atomic<bool> spatialReverbEnabled_ {true};
    std::atomic<bool> parametricEqEnabled_ {true};
    std::atomic<bool> deEsserEnabled_ {true};
    std::atomic<bool> vocalDynamicsEnabled_ {true};
    std::atomic<bool> pitchCorrectionEnabled_ {false};
    std::atomic<float> pitchCorrectionStrength_ {0.0F};
    std::atomic<float> accompanimentPitchShift_ {0.0F};
    std::atomic<std::uint32_t> speakerRampFramesRemaining_ {0};

    // Full 5-Layer Professional DSP Pipeline
    AcousticEchoCanceller aec_;
    AcousticDelayEstimator delayEstimator_;
    AntiHowlingShifter antiHowling_;
    DynamicNotchFilter notchFilter_;
    PitchCorrector pitchCorrector_;
    AccompanimentPitchShifter accompanimentPitchShifter_;
    VocalDynamics vocalDynamics_;
    DeEsser deEsser_;
    ParametricEQ parametricEq_;
    SpatialReverb spatialReverb_;
    LookaheadLimiter limiter_;
    DualTrackRecorder recorder_;
    FeedbackGainGuard gainGuard_;

    std::vector<float> musicWorkBuffer_;
    std::vector<float> rawVocalWorkBuffer_;
    std::vector<int16_t> dryVocalWorkBuffer_;
    std::vector<float> masterRefBuffer_;

    // 2nd-Order Butterworth Bandpass (120Hz HPF + 7.5kHz LPF)
    float speakerHpfS1_ {0.0F};
    float speakerHpfS2_ {0.0F};
    float speakerLpfS1_ {0.0F};
    float speakerLpfS2_ {0.0F};
    StageMetrics lastStageMetrics_ {};
};

} // namespace karaoke

namespace pivomic {
using RealtimeMixer = karaoke::RealtimeMixer;
using ReverbPreset = karaoke::ReverbPreset;
using AudioRouteMode = karaoke::AudioRouteMode;
}

#endif // PIVOMIC_KARAOKE_REALTIME_MIXER_H
