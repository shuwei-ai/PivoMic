#ifndef PIVOMIC_KARAOKE_FEEDBACK_GAIN_GUARD_H
#define PIVOMIC_KARAOKE_FEEDBACK_GAIN_GUARD_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace karaoke {

/**
 * @brief State-Machine Driven Loop Gain Guard for Speaker Karaoke.
 *
 * Replaces naive absolute-energy PID suppressor to eliminate "vocal pumping/ducking"
 * on loud singing, while providing instantaneous (2~5ms) attenuation when exponential
 * acoustic feedback runaway occurs.
 *
 * States:
 * - Normal: Unity transmission (1.0x gain).
 * - Alert: Rapid 2~5ms fast-duck down to 0.35x ~ 0.45x when explosive feedback dE/dt is detected.
 * - Clamped: Hard clamp (0.10x) on sustained clipping / uncontrollable runaway.
 * - Recovery: Smooth, click-free linear ramp-back (0.5 dB / 100ms, ~1.5s) to unity gain once stable.
 */
class FeedbackGainGuard final {
public:
    static constexpr std::size_t kControlBlockSize = 64; // ~1.33ms @ 48kHz
    static constexpr float kMinGainFactor = 0.08F;       // -22dB max emergency ducking
    static constexpr float kAlertGainFactor = 0.40F;     // -8dB fast safety ducking

    enum class GuardState {
        Normal,
        Alert,
        Clamped,
        Recovery
    };

    explicit FeedbackGainGuard(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
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

    void SetEnabled(bool enabled) noexcept { enabled_ = enabled; }
    [[nodiscard]] bool IsEnabled() const noexcept { return enabled_; }

    [[nodiscard]] float CurrentGainFactor() const noexcept { return currentSmoothedGain_; }
    [[nodiscard]] GuardState State() const noexcept { return state_; }

    /**
     * @brief External trigger from HowlingDetector when multi-frequency runaway or sharp resonance begins.
     */
    void TriggerAlert(float targetGain = kAlertGainFactor) noexcept
    {
        if (!enabled_) return;
        targetGain_ = std::clamp(targetGain, kMinGainFactor, 1.0F);
        state_ = GuardState::Alert;
        holdCounter_ = static_cast<uint32_t>(sampleRate_ * 0.15F); // Hold for 150ms before recovery
        CalculateSlew(0.003F); // Fast 3ms attack
    }

    /**
     * @brief Process single sample and return smooth speaker vocal gain multiplier [kMinGainFactor, 1.0F].
     */
    [[nodiscard]] float ProcessSample(float input) noexcept
    {
        if (!enabled_) {
            return 1.0F;
        }

        const float absVal = std::fabs(input);
        blockPeak_ = std::max(blockPeak_, absVal);
        blockEnergySum_ += absVal * absVal;
        ++sampleCounter_;

        if (sampleCounter_ >= kControlBlockSize) {
            ExecuteControlStep();
            sampleCounter_ = 0;
            blockPeak_ = 0.0F;
            blockEnergySum_ = 0.0F;
        }

        // Linear interpolation towards target gain
        if (slewSamplesRemaining_ > 0) {
            currentSmoothedGain_ += gainSlewRate_;
            --slewSamplesRemaining_;
        } else {
            currentSmoothedGain_ = targetGain_;
        }

        return currentSmoothedGain_;
    }

    void Reset() noexcept
    {
        sampleCounter_ = 0;
        blockPeak_ = 0.0F;
        blockEnergySum_ = 0.0F;
        prevBlockEnergy_ = 0.0F;
        filteredDerivative_ = 0.0F;
        state_ = GuardState::Normal;
        targetGain_ = 1.0F;
        currentSmoothedGain_ = 1.0F;
        gainSlewRate_ = 0.0F;
        slewSamplesRemaining_ = 0;
        holdCounter_ = 0;
        clipStreak_ = 0;
        growthStreak_ = 0;
    }

private:
    void CalculateSlew(float durationSeconds) noexcept
    {
        const uint32_t totalSamples = std::max<uint32_t>(1, static_cast<uint32_t>(static_cast<float>(sampleRate_) * durationSeconds));
        slewSamplesRemaining_ = totalSamples;
        gainSlewRate_ = (targetGain_ - currentSmoothedGain_) / static_cast<float>(totalSamples);
    }

    void ExecuteControlStep() noexcept
    {
        const float currentRms = std::sqrt(blockEnergySum_ / static_cast<float>(kControlBlockSize));
        const float currentEnergy = std::max(currentRms, blockPeak_ * 0.7F);

        // 1. Derivative tracking: dE/dt
        const float rawDerivative = (currentEnergy - prevBlockEnergy_) / std::max(dt_, 1e-6F);
        filteredDerivative_ += 0.35F * (rawDerivative - filteredDerivative_);
        prevBlockEnergy_ = currentEnergy;

        // Track compounding growth streak: true feedback compounds across multiple blocks (dt * 3 ~ 4ms)
        if (currentEnergy > 0.30F && rawDerivative > 15.0F) {
            growthStreak_++;
        } else {
            growthStreak_ = 0;
        }

        // 2. Track hard clipping
        if (blockPeak_ >= 0.96F) {
            clipStreak_++;
        } else if (clipStreak_ > 0) {
            clipStreak_--;
        }

        // 3. State machine evaluation
        switch (state_) {
            case GuardState::Normal: {
                // Condition for Feedback Runaway Alert:
                // Compounding growth streak (>= 3 consecutive exploding blocks),
                // or multiple blocks of hard digital clipping
                if (growthStreak_ >= 3 || clipStreak_ >= 3) {
                    state_ = GuardState::Alert;
                    targetGain_ = kAlertGainFactor;
                    holdCounter_ = static_cast<uint32_t>(sampleRate_ * 0.15F); // 150ms hold
                    CalculateSlew(0.003F); // 3ms fast attack
                } else if (clipStreak_ >= 8) {
                    state_ = GuardState::Clamped;
                    targetGain_ = kMinGainFactor;
                    holdCounter_ = static_cast<uint32_t>(sampleRate_ * 0.30F);
                    CalculateSlew(0.002F); // 2ms emergency clamp
                }
                break;
            }

            case GuardState::Alert: {
                if (clipStreak_ >= 6 || (growthStreak_ >= 5 && currentEnergy > 0.7F)) {
                    // Escalation to Clamped
                    state_ = GuardState::Clamped;
                    targetGain_ = kMinGainFactor;
                    holdCounter_ = static_cast<uint32_t>(sampleRate_ * 0.30F);
                    CalculateSlew(0.002F);
                } else if (holdCounter_ > 0) {
                    const uint32_t consumed = std::min<uint32_t>(holdCounter_, kControlBlockSize);
                    holdCounter_ -= consumed;
                } else {
                    // Ready to begin recovery
                    state_ = GuardState::Recovery;
                    targetGain_ = 1.0F;
                    CalculateSlew(1.5F); // 1.5s smooth ramp back
                }
                break;
            }

            case GuardState::Clamped: {
                if (holdCounter_ > 0) {
                    const uint32_t consumed = std::min<uint32_t>(holdCounter_, kControlBlockSize);
                    holdCounter_ -= consumed;
                } else if (currentEnergy < 0.25F && clipStreak_ == 0) {
                    state_ = GuardState::Recovery;
                    targetGain_ = 1.0F;
                    CalculateSlew(2.0F); // 2.0s slow recovery from clamp
                }
                break;
            }

            case GuardState::Recovery: {
                // If feedback suddenly returns during recovery, jump back to Alert immediately!
                if (filteredDerivative_ > 18.0F || clipStreak_ >= 2) {
                    state_ = GuardState::Alert;
                    targetGain_ = kAlertGainFactor;
                    holdCounter_ = static_cast<uint32_t>(sampleRate_ * 0.20F);
                    CalculateSlew(0.003F);
                } else if (slewSamplesRemaining_ == 0 && std::fabs(currentSmoothedGain_ - 1.0F) < 0.01F) {
                    state_ = GuardState::Normal;
                    currentSmoothedGain_ = 1.0F;
                    targetGain_ = 1.0F;
                }
                break;
            }
        }
    }

    uint32_t sampleRate_ {48000};
    float dt_ {0.00133F};
    bool enabled_ {true};

    GuardState state_ {GuardState::Normal};
    std::size_t sampleCounter_ {0};
    float blockPeak_ {0.0F};
    float blockEnergySum_ {0.0F};
    float prevBlockEnergy_ {0.0F};
    float filteredDerivative_ {0.0F};
    uint32_t clipStreak_ {0};
    uint32_t growthStreak_ {0};
    uint32_t holdCounter_ {0};

    float targetGain_ {1.0F};
    float currentSmoothedGain_ {1.0F};
    float gainSlewRate_ {0.0F};
    uint32_t slewSamplesRemaining_ {0};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_FEEDBACK_GAIN_GUARD_H
