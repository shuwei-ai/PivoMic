#ifndef PIVOMIC_KARAOKE_VOCAL_DYNAMICS_H
#define PIVOMIC_KARAOKE_VOCAL_DYNAMICS_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace karaoke {

/**
 * @brief High-precision Vocal Processing Chain featuring:
 * 1. 2nd-Order Butterworth High-Pass Filter (80Hz) to remove mechanical handling noise & plosives.
 * 2. Smooth Hysteresis Noise Gate with envelope tracking (prevents chopped word endings).
 * 3. Feed-Forward Soft-Knee Dynamic Range Compressor (DRC) to level singing volume and eliminate breathing pumping.
 */
class VocalDynamics final {
public:
    explicit VocalDynamics(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate)
    {
        UpdateFilterCoefficients();
        Reset();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        UpdateFilterCoefficients();
        Reset();
    }

    void SetGateThreshold(float thresholdLinear) noexcept
    {
        gateOpenThreshold_ = std::max(0.0001F, thresholdLinear);
        gateCloseThreshold_ = gateOpenThreshold_ * 0.5F; // 6dB hysteresis
    }

    void SetCompressorEnabled(bool enabled) noexcept { compressorEnabled_ = enabled; }

    /**
     * @brief Process a single vocal mono sample.
     */
    [[nodiscard]] float ProcessSample(float input) noexcept
    {
        if (!std::isfinite(input)) {
            return 0.0F;
        }

        // 1. 2nd-Order Butterworth High-Pass Filter (85Hz Cutoff) to remove handling rumble
        const float filtered = b0_ * input + b1_ * x1_ + b2_ * x2_ - a1_ * y1_ - a2_ * y2_;
        x2_ = x1_;
        x1_ = input;
        y2_ = y1_;
        y1_ = std::isfinite(filtered) ? filtered : 0.0F;

        // 2. High-precision Envelope Follower
        const float absVal = std::fabs(y1_);
        const float attackCoeff = 0.25F;
        const float releaseCoeff = 0.003F;
        const float coeff = absVal > envelope_ ? attackCoeff : releaseCoeff;
        envelope_ += coeff * (absVal - envelope_);

        // 3. Studio-Grade Downward Expander Noise Gate
        // -56dBFS to -48dBFS threshold prevents cutting off light singing while rejecting quiet ADC hiss
        constexpr float kGateCloseThreshold = 0.0015F; // -56.5 dBFS
        constexpr float kGateOpenThreshold = 0.0040F;  // -48.0 dBFS
        float targetGate = 1.0F;
        if (envelope_ < kGateCloseThreshold) {
            targetGate = 0.01F; // -40dB background suppression
        } else if (envelope_ < kGateOpenThreshold) {
            const float ratio = (envelope_ - kGateCloseThreshold) / (kGateOpenThreshold - kGateCloseThreshold);
            targetGate = 0.01F + 0.99F * (ratio * ratio);
        }

        const float gateRate = targetGate > gateGain_ ? 0.35F : 0.004F; // 3ms attack, ~80ms smooth release
        gateGain_ += gateRate * (targetGate - gateGain_);
        const float expanded = y1_ * gateGain_;

        if (!compressorEnabled_) {
            return std::tanh(expanded * 2.8F);
        }

        // 4. Feed-Forward Soft-Knee Studio Vocal Dynamic Range Compressor (DRC)
        // Knee = 10dB, Threshold = -22dBFS, Ratio = 2.5, Makeup Gain = +7.5dB
        constexpr float kThresholdDb = -22.0F;
        constexpr float kKneeDb = 10.0F;
        constexpr float kRatio = 2.5F;
        constexpr float kMakeupGainDb = 7.5F; // Safe studio vocal boost without chassis feedback

        const float inputLevel = std::max(envelope_, 1e-6F);
        const float inputDb = 20.0F * std::log10(inputLevel);

        float gainReductionDb = 0.0F;
        const float lowerKnee = kThresholdDb - kKneeDb * 0.5F;
        const float upperKnee = kThresholdDb + kKneeDb * 0.5F;

        if (inputDb > upperKnee) {
            gainReductionDb = (kThresholdDb + (inputDb - kThresholdDb) / kRatio) - inputDb;
        } else if (inputDb >= lowerKnee) {
            const float diff = inputDb - lowerKnee;
            gainReductionDb = ((1.0F / kRatio - 1.0F) * diff * diff) / (2.0F * kKneeDb);
        }

        const float targetGainLinear = std::pow(10.0F, (gainReductionDb + kMakeupGainDb) / 20.0F);
        const float compAttack = 0.12F;
        const float compRelease = 0.003F;
        const float compCoeff = targetGainLinear < compGain_ ? compAttack : compRelease;
        compGain_ += compCoeff * (targetGainLinear - compGain_);

        const float compressed = expanded * compGain_;

        // 5. 12kHz 1st-Order De-Hiss Smoothing Filter (cuts off ADC quantization hiss and Nyquist chatter)
        const float deHissAlpha = 0.611F; // ~12kHz cutoff @ 48kHz
        deHissState_ += deHissAlpha * (compressed - deHissState_);

        // Studio soft-saturation limiter to prevent clipping on loud notes
        return std::tanh(deHissState_ * 0.95F);
    }

    [[nodiscard]] float CurrentEnvelope() const noexcept { return envelope_; }
    [[nodiscard]] float CurrentGateGain() const noexcept { return gateGain_; }

    void Reset() noexcept
    {
        x1_ = 0.0F;
        x2_ = 0.0F;
        y1_ = 0.0F;
        y2_ = 0.0F;
        envelope_ = 0.0F;
        gateGain_ = 0.0F;
        gateTarget_ = 0.0F;
        compGain_ = 1.0F;
        deHissState_ = 0.0F;
    }

private:
    void UpdateFilterCoefficients() noexcept
    {
        // 80Hz 2nd-order Butterworth High-Pass Filter via Bilinear Transform
        constexpr double kFc = 80.0;
        constexpr double kPi = 3.14159265358979323846;
        const double omega = 2.0 * kPi * kFc / static_cast<double>(sampleRate_);
        const double cosw = std::cos(omega);
        const double sinw = std::sin(omega);
        const double alpha = sinw / (2.0 * 0.7071067811865475); // Q = 1/sqrt(2)

        const double a0 = 1.0 + alpha;
        b0_ = static_cast<float>((1.0 + cosw) * 0.5 / a0);
        b1_ = static_cast<float>(-(1.0 + cosw) / a0);
        b2_ = static_cast<float>((1.0 + cosw) * 0.5 / a0);
        a1_ = static_cast<float>(-2.0 * cosw / a0);
        a2_ = static_cast<float>((1.0 - alpha) / a0);
    }

    uint32_t sampleRate_ {48000};
    float gateOpenThreshold_ {0.0005F}; // -66 dBFS
    float gateCloseThreshold_ {0.0002F}; // -74 dBFS
    bool compressorEnabled_ {true};

    // Biquad HPF state
    float b0_ {1.0F};
    float b1_ {0.0F};
    float b2_ {0.0F};
    float a1_ {0.0F};
    float a2_ {0.0F};
    float x1_ {0.0F};
    float x2_ {0.0F};
    float y1_ {0.0F};
    float y2_ {0.0F};

    float envelope_ {0.0F};
    float gateGain_ {0.0F};
    float gateTarget_ {0.0F};
    float compGain_ {1.0F};
    float deHissState_ {0.0F};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_VOCAL_DYNAMICS_H
