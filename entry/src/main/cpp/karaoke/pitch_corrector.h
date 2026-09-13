#ifndef PIVOMIC_KARAOKE_PITCH_CORRECTOR_H
#define PIVOMIC_KARAOKE_PITCH_CORRECTOR_H

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace karaoke {

enum class PitchScaleType : uint32_t {
    Chromatic = 0, // 12-Tone Chromatic (半音阶)
    Major = 1,     // Natural Major (自然大调)
    Minor = 2,     // Natural Minor (自然小调)
    Pentatonic = 3 // Major Pentatonic (五声音阶)
};

/**
 * @brief Studio-grade Real-time Vocal Pitch Detection & Scale Snap Auto-Tune Engine.
 *
 * Implements:
 * 1. Fast Normalized Autocorrelation Function (NACF) with energy thresholding.
 * 2. Continuous MIDI note quantizer (Chromatic, Major, Minor, Pentatonic).
 * 3. Exponential moving average (EMA) pitch glide smoothing.
 * 4. Dual-grain Hann-windowed Constant Overlap-Add (COLA) pitch shifting (100% click-free).
 */
class PitchCorrector final {
public:
    static constexpr std::size_t kAnalysisWindow = 1024; // ~21.3ms @ 48kHz
    static constexpr std::size_t kGrainSize = 1024;      // ~21.3ms grain window
    static constexpr float kMinPitchHz = 65.0F;          // C2
    static constexpr float kMaxPitchHz = 1050.0F;        // C6
    static constexpr float kTwoPi = 6.28318530717958647692F;

    explicit PitchCorrector(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
          buffer_(kGrainSize * 4, 0.0F),
          grainBuffer_(kAnalysisWindow, 0.0F)
    {
        SetSampleRate(sampleRate_);
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        minLag_ = static_cast<std::size_t>(sampleRate_ / kMaxPitchHz);
        maxLag_ = static_cast<std::size_t>(sampleRate_ / kMinPitchHz);
        Reset();
    }

    void SetEnabled(bool enabled) noexcept { enabled_ = enabled; }
    [[nodiscard]] bool IsEnabled() const noexcept { return enabled_; }

    void SetStrength(float strength) noexcept
    {
        strength_ = std::max(0.0F, std::min(strength, 1.0F));
    }
    [[nodiscard]] float Strength() const noexcept { return strength_; }

    void SetScale(PitchScaleType scale, uint32_t rootNote = 0) noexcept
    {
        scaleType_ = scale;
        rootNote_ = rootNote % 12;
    }

    [[nodiscard]] float DetectedPitchHz() const noexcept { return detectedPitchHz_; }
    [[nodiscard]] float TargetPitchHz() const noexcept { return targetPitchHz_; }
    [[nodiscard]] bool IsVoiced() const noexcept { return isVoiced_; }

    /**
     * @brief Process a single vocal sample with smooth click-free Auto-Tune.
     */
    [[nodiscard]] float ProcessSample(float input) noexcept
    {
        if (!enabled_ || strength_ <= 0.001F || !std::isfinite(input)) {
            return input;
        }

        buffer_[writePos_] = input;
        writePos_ = (writePos_ + 1) % buffer_.size();
        ++sampleCounter_;

        // Periodically run pitch detection every 128 samples (~2.67ms @ 48kHz)
        if (sampleCounter_ >= 128) {
            sampleCounter_ = 0;
            DetectAndCalculatePitch();
        }

        // Smoothly interpolate current pitch ratio towards target
        pitchRatio_ += 0.05F * (targetPitchRatio_ - pitchRatio_);

        if (!isVoiced_ || std::fabs(pitchRatio_ - 1.0F) < 0.003F) {
            return input;
        }

        // Dual-tap Hann-windowed overlap-add pitch shifter (Constant Overlap-Add COLA)
        const float rate = pitchRatio_ - 1.0F;
        phase0_ += rate;
        while (phase0_ >= static_cast<float>(kGrainSize)) {
            phase0_ -= static_cast<float>(kGrainSize);
        }
        while (phase0_ < 0.0F) {
            phase0_ += static_cast<float>(kGrainSize);
        }

        float phase1 = phase0_ + static_cast<float>(kGrainSize) * 0.5F;
        if (phase1 >= static_cast<float>(kGrainSize)) {
            phase1 -= static_cast<float>(kGrainSize);
        }

        // Exact Hann window: win0 + win1 == 1.0 at all times
        const float win0 = 0.5F * (1.0F - std::cos(kTwoPi * phase0_ / static_cast<float>(kGrainSize)));
        const float win1 = 0.5F * (1.0F - std::cos(kTwoPi * phase1 / static_cast<float>(kGrainSize)));

        const auto bufSize = buffer_.size();
        const float delay0 = phase0_ + static_cast<float>(kGrainSize) * 0.5F;
        const float delay1 = phase1 + static_cast<float>(kGrainSize) * 0.5F;

        const float readIdx0 = static_cast<float>(writePos_ + 4 * bufSize) - delay0;
        const float readIdx1 = static_cast<float>(writePos_ + 4 * bufSize) - delay1;

        const auto idx0_a = static_cast<std::size_t>(readIdx0) % bufSize;
        const auto idx0_b = (idx0_a + 1) % bufSize;
        const float frac0 = readIdx0 - std::floor(readIdx0);
        const float sample0 = buffer_[idx0_a] * (1.0F - frac0) + buffer_[idx0_b] * frac0;

        const auto idx1_a = static_cast<std::size_t>(readIdx1) % bufSize;
        const auto idx1_b = (idx1_a + 1) % bufSize;
        const float frac1 = readIdx1 - std::floor(readIdx1);
        const float sample1 = buffer_[idx1_a] * (1.0F - frac1) + buffer_[idx1_b] * frac1;

        const float pitchShifted = sample0 * win0 + sample1 * win1;

        // Crossfade between original and pitch-corrected output based on strength
        return input * (1.0F - strength_) + pitchShifted * strength_;
    }

    void Process(const float* input, float* output, std::size_t frames) noexcept
    {
        if (input == nullptr || output == nullptr || frames == 0) return;
        for (std::size_t i = 0; i < frames; ++i) {
            output[i] = ProcessSample(input[i]);
        }
    }

    [[nodiscard]] float QuantizePitchToScale(float freqHz) const noexcept
    {
        if (freqHz <= 10.0F) return freqHz;

        // Convert Hz to continuous MIDI note number: midi = 69 + 12 * log2(freq / 440)
        const float midiNote = 69.0F + 12.0F * std::log2(freqHz / 440.0F);
        const int noteInt = static_cast<int>(std::round(midiNote));

        // Find nearest allowed note in the target scale
        int bestNote = noteInt;
        int minDistance = 999;

        for (int candidate = noteInt - 3; candidate <= noteInt + 3; ++candidate) {
            if (IsNoteInScale(candidate)) {
                const int dist = std::abs(candidate - noteInt);
                if (dist < minDistance) {
                    minDistance = dist;
                    bestNote = candidate;
                }
            }
        }

        // Target frequency: f = 440 * 2^((bestNote - 69) / 12)
        return 440.0F * std::pow(2.0F, static_cast<float>(bestNote - 69) / 12.0F);
    }

    [[nodiscard]] bool IsNoteInScale(int midiNote) const noexcept
    {
        const int chroma = (midiNote % 12 + 12) % 12;
        const int relChroma = (chroma - static_cast<int>(rootNote_) + 12) % 12;

        switch (scaleType_) {
            case PitchScaleType::Chromatic:
                return true;
            case PitchScaleType::Major:
                return (relChroma == 0 || relChroma == 2 || relChroma == 4 ||
                        relChroma == 5 || relChroma == 7 || relChroma == 9 || relChroma == 11);
            case PitchScaleType::Minor:
                return (relChroma == 0 || relChroma == 2 || relChroma == 3 ||
                        relChroma == 5 || relChroma == 7 || relChroma == 8 || relChroma == 10);
            case PitchScaleType::Pentatonic:
                return (relChroma == 0 || relChroma == 2 || relChroma == 4 ||
                        relChroma == 7 || relChroma == 9);
        }
        return true;
    }

    void Reset() noexcept
    {
        std::fill(buffer_.begin(), buffer_.end(), 0.0F);
        writePos_ = 0;
        sampleCounter_ = 0;
        detectedPitchHz_ = 0.0F;
        targetPitchHz_ = 0.0F;
        pitchRatio_ = 1.0F;
        targetPitchRatio_ = 1.0F;
        phase0_ = 0.0F;
        isVoiced_ = false;
    }

private:
    void DetectAndCalculatePitch() noexcept
    {
        // 1. Extract analysis window
        const auto bufSize = buffer_.size();
        float energy = 0.0F;
        for (std::size_t i = 0; i < kAnalysisWindow; ++i) {
            const std::size_t idx = (writePos_ + bufSize - kAnalysisWindow + i) % bufSize;
            const float s = buffer_[idx];
            grainBuffer_[i] = s;
            energy += s * s;
        }

        // Silence / Noise floor check
        if (energy < 1e-4F) {
            isVoiced_ = false;
            detectedPitchHz_ = 0.0F;
            targetPitchHz_ = 0.0F;
            targetPitchRatio_ = 1.0F;
            return;
        }

        // 2. Normalized Autocorrelation Function (NACF)
        float maxCorr = 0.0F;
        std::size_t bestLag = 0;

        const std::size_t searchMin = std::max(minLag_, std::size_t{2});
        const std::size_t searchMax = std::min(maxLag_, kAnalysisWindow / 2);

        for (std::size_t lag = searchMin; lag <= searchMax; ++lag) {
            float corr = 0.0F;
            float e1 = 0.0F;
            float e2 = 0.0F;
            for (std::size_t i = 0; i < kAnalysisWindow - lag; ++i) {
                const float s1 = grainBuffer_[i];
                const float s2 = grainBuffer_[i + lag];
                corr += s1 * s2;
                e1 += s1 * s1;
                e2 += s2 * s2;
            }
            const float denom = std::sqrt(e1 * e2 + 1e-8F);
            const float ncorr = corr / denom;
            if (ncorr > maxCorr) {
                maxCorr = ncorr;
                bestLag = lag;
            }
        }

        // Voiced threshold: autocorrelation correlation coefficient > 0.60
        if (maxCorr > 0.60F && bestLag > 0) {
            isVoiced_ = true;
            const float fineLag = static_cast<float>(bestLag);
            detectedPitchHz_ = static_cast<float>(sampleRate_) / fineLag;

            // 3. Snap to scale target
            targetPitchHz_ = QuantizePitchToScale(detectedPitchHz_);

            // 4. Calculate Pitch Correction Ratio (capped to [-3, +3] semitones)
            if (detectedPitchHz_ > 10.0F) {
                const float idealRatio = targetPitchHz_ / detectedPitchHz_;
                const float boundedRatio = std::clamp(idealRatio, 0.8409F, 1.1892F); // ±3 semitones
                targetPitchRatio_ = 1.0F + strength_ * (boundedRatio - 1.0F);
            }
        } else {
            isVoiced_ = false;
            targetPitchRatio_ = 1.0F;
        }
    }

    uint32_t sampleRate_ {48000};
    bool enabled_ {false};
    float strength_ {0.0F};
    PitchScaleType scaleType_ {PitchScaleType::Chromatic};
    uint32_t rootNote_ {0}; // 0 = C

    std::vector<float> buffer_;
    std::vector<float> grainBuffer_;
    std::size_t writePos_ {0};
    std::size_t minLag_ {45};
    std::size_t maxLag_ {738};
    std::size_t sampleCounter_ {0};

    float detectedPitchHz_ {0.0F};
    float targetPitchHz_ {0.0F};
    float pitchRatio_ {1.0F};
    float targetPitchRatio_ {1.0F};
    float phase0_ {0.0F};
    bool isVoiced_ {false};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_PITCH_CORRECTOR_H
