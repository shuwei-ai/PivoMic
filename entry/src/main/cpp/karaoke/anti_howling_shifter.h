#ifndef PIVOMIC_KARAOKE_ANTI_HOWLING_SHIFTER_H
#define PIVOMIC_KARAOKE_ANTI_HOWLING_SHIFTER_H

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace karaoke {

/**
 * @brief High-efficiency Single-Sideband (SSB) Frequency Shifter for Acoustic Feedback Cancellation (AFC).
 *
 * Employs a dual 4-stage IIR all-pass Hilbert phase splitter (Direct Form II Transposed)
 * to generate in-phase (I) and quadrature (Q) signal components with broadband ~90° phase difference,
 * modulated by a quadrature sinusoidal carrier at deltaHz (default: +4.0 Hz).
 *
 * Shifting frequency by +4Hz breaks phase-coherence in acoustic feedback loops between speaker and
 * microphone, boosting Maximum Stable Gain (MSG) by 6-10 dB without perceptible pitch shift.
 */
class AntiHowlingShifter final {
public:
    explicit AntiHowlingShifter(uint32_t sampleRate = 48000, float deltaHz = 5.0F) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
          deltaHz_(deltaHz),
          phaseIncrement_(2.0F * static_cast<float>(kPi) * deltaHz_ / static_cast<float>(sampleRate_))
    {
        InitializeCoefficients();
        Reset();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        phaseIncrement_ = 2.0F * static_cast<float>(kPi) * deltaHz_ / static_cast<float>(sampleRate_);
        Reset();
    }

    void SetFrequencyShift(float deltaHz) noexcept
    {
        deltaHz_ = deltaHz;
        phaseIncrement_ = 2.0F * static_cast<float>(kPi) * deltaHz_ / static_cast<float>(sampleRate_);
    }

    [[nodiscard]] float FrequencyShift() const noexcept { return deltaHz_; }

    void SetEnabled(bool enabled) noexcept { enabled_ = enabled; }
    [[nodiscard]] bool IsEnabled() const noexcept { return enabled_; }

    /**
     * @brief Process a single audio sample.
     */
    [[nodiscard]] float ProcessSample(float input) noexcept
    {
        if (!enabled_ || deltaHz_ == 0.0F) {
            return input;
        }

        // Dual 4-stage IIR all-pass Hilbert phase splitter in Direct Form II Transposed
        float xA = input;
        for (std::size_t i = 0; i < 4; ++i) {
            const float y = coeffsA_[i] * xA + stateA_[i];
            stateA_[i] = xA - coeffsA_[i] * y;
            xA = y;
        }

        float xB = input;
        for (std::size_t i = 0; i < 4; ++i) {
            const float y = coeffsB_[i] * xB + stateB_[i];
            stateB_[i] = xB - coeffsB_[i] * y;
            xB = y;
        }

        // Single Sideband up-shift modulation with sqrt(0.5) unity power normalization
        constexpr float kNorm = 0.70710678F;
        const float cosVal = std::cos(phase_);
        const float sinVal = std::sin(phase_);
        const float output = (xA * cosVal - xB * sinVal) * kNorm;

        phase_ += phaseIncrement_;
        if (phase_ >= 2.0F * static_cast<float>(kPi)) {
            phase_ -= 2.0F * static_cast<float>(kPi);
        }

        return output;
    }

    /**
     * @brief Process a block of samples in place.
     */
    void Process(float *samples, std::size_t count) noexcept
    {
        if (samples == nullptr || count == 0) {
            return;
        }
        for (std::size_t i = 0; i < count; ++i) {
            samples[i] = ProcessSample(samples[i]);
        }
    }

    void Reset() noexcept
    {
        stateA_.fill(0.0F);
        stateB_.fill(0.0F);
        phase_ = 0.0F;
    }

private:
    void InitializeCoefficients() noexcept
    {
        // 4th order optimal all-pass phase splitter coefficients
        coeffsA_ = {0.161758F, 0.733029F, 0.94535F, 0.990598F};
        coeffsB_ = {0.471187F, 0.879581F, 0.97632F, 0.997499F};
    }

    static constexpr double kPi = 3.14159265358979323846;

    uint32_t sampleRate_ {48000};
    float deltaHz_ {4.0F};
    float phaseIncrement_ {0.0F};
    float phase_ {0.0F};
    bool enabled_ {true};

    std::array<float, 4> coeffsA_ {};
    std::array<float, 4> coeffsB_ {};
    std::array<float, 4> stateA_ {};
    std::array<float, 4> stateB_ {};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_ANTI_HOWLING_SHIFTER_H
