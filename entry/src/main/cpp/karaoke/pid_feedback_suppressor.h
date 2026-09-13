#ifndef PIVOMIC_KARAOKE_PID_FEEDBACK_SUPPRESSOR_H
#define PIVOMIC_KARAOKE_PID_FEEDBACK_SUPPRESSOR_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace karaoke {

/**
 * @brief High-precision Acoustic Energy Growth-Rate PID Feedback Suppressor.
 *
 * Employs a discrete closed-loop PID regulator operating on short-time microphone
 * vocal energy and its 1st-order derivative (dE/dt) to detect exponential feedback
 * acceleration and preemptively duck speaker ear-return gain before howling manifests.
 */
class PidFeedbackSuppressor final {
public:
    static constexpr std::size_t kControlBlockSize = 64; // ~1.33ms @ 48kHz
    static constexpr float kSafeEnergyThreshold = 0.20F; // Highly responsive setpoint
    static constexpr float kMinGainFactor = 0.10F;       // -20dB max suppression

    explicit PidFeedbackSuppressor(uint32_t sampleRate = 48000,
                                   float kp = 2.6F,
                                   float ki = 1.2F,
                                   float kd = 0.15F) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
          kp_(kp),
          ki_(ki),
          kd_(kd),
          dt_(static_cast<float>(kControlBlockSize) / static_cast<float>(sampleRate_))
    {
        Reset();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        dt_ = static_cast<float>(kControlBlockSize) / static_cast<float>(sampleRate_);
        Reset();
    }

    void SetTunings(float kp, float ki, float kd) noexcept
    {
        kp_ = std::max(0.0F, kp);
        ki_ = std::max(0.0F, ki);
        kd_ = std::max(0.0F, kd);
    }

    void SetEnabled(bool enabled) noexcept { enabled_ = enabled; }
    [[nodiscard]] bool IsEnabled() const noexcept { return enabled_; }

    [[nodiscard]] float CurrentGainFactor() const noexcept { return currentSmoothedGain_; }
    [[nodiscard]] float CurrentIntegral() const noexcept { return integralState_; }

    /**
     * @brief Process a single sample and return the PID regulated speaker gain multiplier.
     * @param micInput Instantaneous raw microphone sample.
     * @return Gain factor [kMinGainFactor, 1.0F] with per-sample smooth interpolation.
     */
    [[nodiscard]] float ProcessSample(float micInput) noexcept
    {
        if (!enabled_) {
            return 1.0F;
        }

        const float absVal = std::fabs(micInput);
        blockPeak_ = std::max(blockPeak_, absVal);
        blockEnergySum_ += absVal * absVal;
        ++sampleCounter_;

        // Execute PID state step every 64 samples (~1.33ms)
        if (sampleCounter_ >= kControlBlockSize) {
            ExecuteControlStep();
            sampleCounter_ = 0;
            blockPeak_ = 0.0F;
            blockEnergySum_ = 0.0F;
        }

        // Per-sample linear slewing to prevent clicks
        currentSmoothedGain_ += gainSlewRate_;
        return currentSmoothedGain_;
    }

    void Reset() noexcept
    {
        sampleCounter_ = 0;
        blockPeak_ = 0.0F;
        blockEnergySum_ = 0.0F;
        lastError_ = 0.0F;
        integralState_ = 0.0F;
        targetGain_ = 1.0F;
        currentSmoothedGain_ = 1.0F;
        gainSlewRate_ = 0.0F;
        differentiatorState_ = 0.0F;
    }

private:
    void ExecuteControlStep() noexcept
    {
        const float rms = std::sqrt(blockEnergySum_ / static_cast<float>(kControlBlockSize));
        const float measuredEnergy = std::max(rms, blockPeak_ * 0.7F);

        // Error: positive when measured energy exceeds the safe acoustic threshold
        const float error = measuredEnergy > kSafeEnergyThreshold ? (measuredEnergy - kSafeEnergyThreshold) : 0.0F;

        // 1. Derivative term (dE/dt) with 1st-order low-pass filter to reject isolated spike noise
        const float rawDerivative = (error - lastError_) / std::max(dt_, 1e-6F);
        differentiatorState_ += 0.40F * (rawDerivative - differentiatorState_);
        const float dTerm = kd_ * std::max(0.0F, differentiatorState_);

        // 2. Proportional term
        const float pTerm = kp_ * error;

        // 3. Integral term with anti-windup clamping
        integralState_ += ki_ * error * dt_;
        // Decay integral slowly when error is zero
        if (error <= 1e-6F) {
            integralState_ *= 0.95F;
        }
        integralState_ = std::max(0.0F, std::min(integralState_, 1.0F - kMinGainFactor));
        const float iTerm = integralState_;

        // Compute raw suppression factor (1.0 = safe full volume, <1.0 = ducked)
        const float totalSuppression = pTerm + iTerm + dTerm;
        targetGain_ = std::max(kMinGainFactor, std::min(1.0F, 1.0F - totalSuppression));

        // Prepare linear slew step for the next 64 samples
        gainSlewRate_ = (targetGain_ - currentSmoothedGain_) / static_cast<float>(kControlBlockSize);
        lastError_ = error;
    }

    uint32_t sampleRate_ {48000};
    float kp_ {1.8F};
    float ki_ {0.5F};
    float kd_ {0.08F};
    float dt_ {64.0F / 48000.0F};
    bool enabled_ {true};

    std::size_t sampleCounter_ {0};
    float blockPeak_ {0.0F};
    float blockEnergySum_ {0.0F};
    float lastError_ {0.0F};
    float integralState_ {0.0F};
    float differentiatorState_ {0.0F};
    float targetGain_ {1.0F};
    float currentSmoothedGain_ {1.0F};
    float gainSlewRate_ {0.0F};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_PID_FEEDBACK_SUPPRESSOR_H
