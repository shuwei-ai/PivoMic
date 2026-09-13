#ifndef PIVOMIC_KARAOKE_DYNAMIC_NOTCH_FILTER_H
#define PIVOMIC_KARAOKE_DYNAMIC_NOTCH_FILTER_H

#include "karaoke/howling_detector.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace karaoke {

/**
 * @brief 8-Channel Dynamic Notch Filter Bank for Anti-Howling Feedback Suppression.
 *
 * Employs 8 Direct Form II Transposed Biquad peaking-cut filters.
 * Supports smooth 5ms coefficient slewing (click-free transitions),
 * 2.0s hold duration, and 1.5s cosine release.
 *
 * Integrated with HowlingDetector for high-precision FFT-based feedback suppression
 * while preventing false triggers on sustained human singing tones.
 */
class DynamicNotchFilter final {
public:
    static constexpr std::size_t kMaxNotches = 8;
    static constexpr std::size_t kSlewSamples = 240; // 5ms @ 48kHz

    explicit DynamicNotchFilter(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
          kHoldSamples_(sampleRate_ * 2), // 2 seconds hold
          detector_(sampleRate_)
    {
        Reset();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        kHoldSamples_ = sampleRate_ * 2;
        detector_.SetSampleRate(sampleRate_);
        Reset();
    }

    void SetEnabled(bool enabled) noexcept { enabled_ = enabled; }
    [[nodiscard]] bool IsEnabled() const noexcept { return enabled_; }

    void SetAutoDetectionEnabled(bool enabled) noexcept
    {
        autoDetectEnabled_ = enabled;
        detector_.SetEnabled(enabled);
    }
    [[nodiscard]] bool IsAutoDetectionEnabled() const noexcept { return autoDetectEnabled_; }

    /**
     * @brief Apply a precomputed notch filter command (e.g. from background detector).
     */
    void ApplyCommand(const NotchCommand &cmd) noexcept
    {
        if (cmd.slot >= kMaxNotches) {
            return;
        }

        auto &n = notches_[cmd.slot];
        n.active = cmd.active;
        n.frequencyHz = cmd.frequencyHz;
        n.depthDb = cmd.depthDb;
        n.q = cmd.q;
        n.holdCounter = kHoldSamples_;

        n.targetB0 = cmd.b0;
        n.targetB1 = cmd.b1;
        n.targetB2 = cmd.b2;
        n.targetA1 = cmd.a1;
        n.targetA2 = cmd.a2;

        if (!n.wasActive) {
            // First time activation: start from unity pass-through and slew to target
            n.currentB0 = 1.0F;
            n.currentB1 = 0.0F;
            n.currentB2 = 0.0F;
            n.currentA1 = 0.0F;
            n.currentA2 = 0.0F;
            n.s1 = 0.0F;
            n.s2 = 0.0F;
            n.wasActive = true;
        }

        n.slewCounter = kSlewSamples;
    }

    /**
     * @brief Apply a batch of notch filter commands.
     */
    void ApplyCommands(const std::vector<NotchCommand> &cmds) noexcept
    {
        for (const auto &cmd : cmds) {
            ApplyCommand(cmd);
        }
    }

    /**
     * @brief Manually assign a notch filter at a target howling frequency.
     */
    void AddNotch(float frequencyHz, float depthDb = 15.0F, float q = 25.0F) noexcept
    {
        if (frequencyHz < 100.0F || frequencyHz > static_cast<float>(sampleRate_) * 0.45F) {
            return;
        }

        // Check if a notch already exists near this frequency (within 2%)
        for (std::size_t i = 0; i < kMaxNotches; ++i) {
            if (notches_[i].active && std::fabs(notches_[i].frequencyHz - frequencyHz) / frequencyHz < 0.02F) {
                notches_[i].holdCounter = kHoldSamples_;
                if (depthDb > notches_[i].depthDb) {
                    ConfigureNotchSlot(i, frequencyHz, depthDb, q);
                }
                return;
            }
        }

        // Find an inactive slot or the slot with lowest holdCounter
        std::size_t targetSlot = 0;
        uint32_t minHold = UINT32_MAX;
        for (std::size_t i = 0; i < kMaxNotches; ++i) {
            if (!notches_[i].active) {
                targetSlot = i;
                break;
            }
            if (notches_[i].holdCounter < minHold) {
                minHold = notches_[i].holdCounter;
                targetSlot = i;
            }
        }

        ConfigureNotchSlot(targetSlot, frequencyHz, depthDb, q);
    }

    [[nodiscard]] std::size_t ActiveNotchCount() const noexcept
    {
        std::size_t count = 0;
        for (std::size_t i = 0; i < kMaxNotches; ++i) {
            if (notches_[i].active) {
                ++count;
            }
        }
        return count;
    }

    /**
     * @brief Process single sample through active notch filter bank.
     */
    [[nodiscard]] float ProcessSample(float input) noexcept
    {
        if (!enabled_ || !std::isfinite(input)) {
            return input;
        }

        // 1. Auto-detection pass if enabled
        if (autoDetectEnabled_) {
            sampleAccumulator_[accumPos_++] = input;
            if (accumPos_ >= 64) {
                tempCommands_.clear();
                if (detector_.Process(sampleAccumulator_.data(), accumPos_, &tempCommands_)) {
                    ApplyCommands(tempCommands_);
                }
                accumPos_ = 0;
            }
        }

        // 2. Cascade active notch filters
        float sample = input;
        for (std::size_t i = 0; i < kMaxNotches; ++i) {
            auto &n = notches_[i];
            if (!n.active && n.currentB0 == 1.0F && n.currentB1 == 0.0F) {
                continue;
            }

            // Click-free linear slewing of coefficients
            if (n.slewCounter > 0) {
                const float factor = 1.0F / static_cast<float>(n.slewCounter);
                n.currentB0 += (n.targetB0 - n.currentB0) * factor;
                n.currentB1 += (n.targetB1 - n.currentB1) * factor;
                n.currentB2 += (n.targetB2 - n.currentB2) * factor;
                n.currentA1 += (n.targetA1 - n.currentA1) * factor;
                n.currentA2 += (n.targetA2 - n.currentA2) * factor;
                --n.slewCounter;
            }

            // Direct Form II Transposed filter execution
            const float y = n.currentB0 * sample + n.s1;
            n.s1 = n.currentB1 * sample - n.currentA1 * y + n.s2;
            n.s2 = n.currentB2 * sample - n.currentA2 * y;
            sample = std::isfinite(y) ? y : 0.0F;

            // Decay hold timer
            if (n.holdCounter > 0) {
                --n.holdCounter;
            } else if (n.active) {
                // Slew back to unity gain (release phase)
                n.active = false;
                n.targetB0 = 1.0F;
                n.targetB1 = 0.0F;
                n.targetB2 = 0.0F;
                n.targetA1 = 0.0F;
                n.targetA2 = 0.0F;
                n.slewCounter = kSlewSamples * 2; // 10ms smooth fade-out
                n.wasActive = false;
            }
        }

        return sample;
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
        for (auto &n : notches_) {
            n.active = false;
            n.wasActive = false;
            n.frequencyHz = 0.0F;
            n.depthDb = 0.0F;
            n.q = 25.0F;
            n.holdCounter = 0;
            n.slewCounter = 0;
            n.currentB0 = 1.0F;
            n.currentB1 = 0.0F;
            n.currentB2 = 0.0F;
            n.currentA1 = 0.0F;
            n.currentA2 = 0.0F;
            n.targetB0 = 1.0F;
            n.targetB1 = 0.0F;
            n.targetB2 = 0.0F;
            n.targetA1 = 0.0F;
            n.targetA2 = 0.0F;
            n.s1 = 0.0F;
            n.s2 = 0.0F;
        }
        detector_.Reset();
        accumPos_ = 0;
        sampleAccumulator_.fill(0.0F);
        tempCommands_.clear();
    }

    [[nodiscard]] HowlingDetector &Detector() noexcept { return detector_; }

private:
    struct NotchSlot {
        bool active {false};
        bool wasActive {false};
        float frequencyHz {0.0F};
        float depthDb {0.0F};
        float q {25.0F};
        uint32_t holdCounter {0};
        uint32_t slewCounter {0};

        // Running smoothed coefficients
        float currentB0 {1.0F};
        float currentB1 {0.0F};
        float currentB2 {0.0F};
        float currentA1 {0.0F};
        float currentA2 {0.0F};

        // Target coefficients to slew toward
        float targetB0 {1.0F};
        float targetB1 {0.0F};
        float targetB2 {0.0F};
        float targetA1 {0.0F};
        float targetA2 {0.0F};

        // Filter state (Direct Form II Transposed)
        float s1 {0.0F};
        float s2 {0.0F};
    };

    void ConfigureNotchSlot(std::size_t i, float frequencyHz, float depthDb, float q) noexcept
    {
        auto &n = notches_[i];
        n.frequencyHz = frequencyHz;
        n.depthDb = depthDb;
        n.q = q;
        n.active = true;
        n.holdCounter = kHoldSamples_;

        float b0 = 1.0F, b1 = 0.0F, b2 = 0.0F, a1 = 0.0F, a2 = 0.0F;
        HowlingDetector::ComputeNotchCoefficients(static_cast<float>(sampleRate_), frequencyHz, depthDb, q,
                                                 b0, b1, b2, a1, a2);

        n.targetB0 = b0;
        n.targetB1 = b1;
        n.targetB2 = b2;
        n.targetA1 = a1;
        n.targetA2 = a2;

        n.currentB0 = b0;
        n.currentB1 = b1;
        n.currentB2 = b2;
        n.currentA1 = a1;
        n.currentA2 = a2;
        n.wasActive = true;
        n.slewCounter = 0;
    }

    uint32_t sampleRate_ {48000};
    uint32_t kHoldSamples_ {96000};
    bool enabled_ {true};
    bool autoDetectEnabled_ {true};

    std::array<NotchSlot, kMaxNotches> notches_ {};
    HowlingDetector detector_;

    std::size_t accumPos_ {0};
    std::array<float, 64> sampleAccumulator_ {};
    std::vector<NotchCommand> tempCommands_ {};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_DYNAMIC_NOTCH_FILTER_H
