#ifndef PIVOMIC_KARAOKE_DE_ESSER_H
#define PIVOMIC_KARAOKE_DE_ESSER_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace karaoke {

/**
 * @brief Dynamic Vocal De-Esser to tame harsh sibilance ("s", "sh", "ch", "ts") between 5.0 kHz and 7.5 kHz.
 *
 * Employs a 2nd-order bandpass filter for sidechain sibilance detection, paired with a dynamic
 * high-shelf attenuation filter that engages only when high-frequency energy spikes above threshold.
 */
class DeEsser final {
public:
    explicit DeEsser(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate)
    {
        UpdateCoefficients();
        Reset();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        UpdateCoefficients();
        Reset();
    }

    void SetThresholdDb(float thresholdDb) noexcept
    {
        thresholdLinear_ = std::pow(10.0F, thresholdDb / 20.0F);
    }

    void SetRatio(float ratio) noexcept
    {
        ratio_ = std::max(1.0F, std::min(ratio, 10.0F));
    }

    void SetEnabled(bool enabled) noexcept { enabled_ = enabled; }
    [[nodiscard]] bool IsEnabled() const noexcept { return enabled_; }

    [[nodiscard]] float ProcessSample(float input) noexcept
    {
        if (!enabled_ || !std::isfinite(input)) {
            return input;
        }

        // 1. Sidechain 2nd-order Bandpass Filter (6 kHz, Q=2.0)
        const float bp = bpB0_ * input + bpB1_ * bpX1_ + bpB2_ * bpX2_ - bpA1_ * bpY1_ - bpA2_ * bpY2_;
        bpX2_ = bpX1_;
        bpX1_ = input;
        bpY2_ = bpY1_;
        bpY1_ = std::isfinite(bp) ? bp : 0.0F;

        // 2. Peak envelope of sibilance band
        const float absBp = std::fabs(bpY1_);
        const float attackCoeff = 0.15F;  // ~1 ms fast attack
        const float releaseCoeff = 0.002F; // ~30 ms release
        const float coeff = absBp > sibilanceEnvelope_ ? attackCoeff : releaseCoeff;
        sibilanceEnvelope_ += coeff * (absBp - sibilanceEnvelope_);

        // 3. Compute dynamic reduction gain
        float targetAttenLinear = 1.0F;
        if (sibilanceEnvelope_ > thresholdLinear_ && thresholdLinear_ > 1e-5F) {
            const float excess = sibilanceEnvelope_ / thresholdLinear_;
            const float excessDb = 20.0F * std::log10(excess);
            const float reductionDb = (excessDb * (1.0F - 1.0F / ratio_));
            targetAttenLinear = std::pow(10.0F, -reductionDb / 20.0F);
            targetAttenLinear = std::max(targetAttenLinear, 0.25F); // max 12dB reduction
        }

        const float gainRate = targetAttenLinear < currentGain_ ? 0.2F : 0.005F;
        currentGain_ += gainRate * (targetAttenLinear - currentGain_);

        // 4. Dynamic attenuation on sibilance band (Subtractive ducking)
        return input - bpY1_ * (1.0F - currentGain_);
    }

    void Process(float *samples, std::size_t count) noexcept
    {
        if (samples == nullptr || count == 0 || !enabled_) {
            return;
        }
        for (std::size_t i = 0; i < count; ++i) {
            samples[i] = ProcessSample(samples[i]);
        }
    }

    void Reset() noexcept
    {
        bpX1_ = 0.0F;
        bpX2_ = 0.0F;
        bpY1_ = 0.0F;
        bpY2_ = 0.0F;
        sibilanceEnvelope_ = 0.0F;
        currentGain_ = 1.0F;
    }

private:
    void UpdateCoefficients() noexcept
    {
        // 6000 Hz Bandpass Filter with Q = 2.0
        constexpr double kFc = 6000.0;
        constexpr double kQ = 2.0;
        constexpr double kPi = 3.14159265358979323846;
        const double w0 = 2.0 * kPi * kFc / static_cast<double>(sampleRate_);
        const double cosw0 = std::cos(w0);
        const double sinw0 = std::sin(w0);
        const double alpha = sinw0 / (2.0 * kQ);

        const double a0 = 1.0 + alpha;
        bpB0_ = static_cast<float>(alpha / a0);
        bpB1_ = 0.0F;
        bpB2_ = static_cast<float>(-alpha / a0);
        bpA1_ = static_cast<float>(-2.0 * cosw0 / a0);
        bpA2_ = static_cast<float>((1.0 - alpha) / a0);
    }

    uint32_t sampleRate_ {48000};
    float thresholdLinear_ {0.0630957344F}; // -24 dBFS
    float ratio_ {3.5F};
    bool enabled_ {true};

    float bpB0_ {0.0F};
    float bpB1_ {0.0F};
    float bpB2_ {0.0F};
    float bpA1_ {0.0F};
    float bpA2_ {0.0F};
    float bpX1_ {0.0F};
    float bpX2_ {0.0F};
    float bpY1_ {0.0F};
    float bpY2_ {0.0F};

    float sibilanceEnvelope_ {0.0F};
    float currentGain_ {1.0F};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_DE_ESSER_H
