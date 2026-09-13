#ifndef PIVOMIC_KARAOKE_PARAMETRIC_EQ_H
#define PIVOMIC_KARAOKE_PARAMETRIC_EQ_H

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace karaoke {

/**
 * @brief 4-Band Studio Parametric Equalizer for vocal enhancement:
 * - Band 0: Low-Shelf (120 Hz, default +1.0 dB) - warm chest resonance
 * - Band 1: Peaking/Bell (1.2 kHz, default -1.5 dB) - reduces nasality and boxiness
 * - Band 2: Peaking/Bell (3.5 kHz, default +2.5 dB) - vocal clarity, intelligibility & presence
 * - Band 3: High-Shelf (10.0 kHz, default +1.5 dB) - air & sheen
 *
 * Implemented using Direct Form II Transposed biquad sections for maximum numerical stability.
 */
class ParametricEQ final {
public:
    enum class FilterType {
        LowShelf,
        Peaking,
        HighShelf
    };

    struct BandConfig {
        FilterType type {FilterType::Peaking};
        float frequencyHz {1000.0F};
        float gainDb {0.0F};
        float q {0.707F};
    };

    explicit ParametricEQ(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate)
    {
        InitializeDefaultBands();
        UpdateCoefficients();
        Reset();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        UpdateCoefficients();
        Reset();
    }

    void SetBand(std::size_t bandIndex, FilterType type, float frequencyHz, float gainDb, float q) noexcept
    {
        if (bandIndex >= bands_.size()) {
            return;
        }
        bands_[bandIndex] = {type, std::max(20.0F, std::min(frequencyHz, sampleRate_ * 0.48F)),
                             std::max(-24.0F, std::min(gainDb, 24.0F)),
                             std::max(0.1F, std::min(q, 10.0F))};
        ComputeBandCoefficients(bandIndex);
    }

    void SetBandGain(std::size_t bandIndex, float gainDb) noexcept
    {
        if (bandIndex >= bands_.size()) {
            return;
        }
        bands_[bandIndex].gainDb = std::max(-24.0F, std::min(gainDb, 24.0F));
        ComputeBandCoefficients(bandIndex);
    }

    [[nodiscard]] const BandConfig& GetBand(std::size_t bandIndex) const noexcept
    {
        static constexpr BandConfig kEmpty {};
        return bandIndex < bands_.size() ? bands_[bandIndex] : kEmpty;
    }

    void SetEnabled(bool enabled) noexcept { enabled_ = enabled; }
    [[nodiscard]] bool IsEnabled() const noexcept { return enabled_; }

    /**
     * @brief Process a single mono sample in place through the 4-band cascade.
     */
    [[nodiscard]] float ProcessSample(float input) noexcept
    {
        if (!enabled_ || !std::isfinite(input)) {
            return input;
        }

        float sample = input;
        for (std::size_t i = 0; i < 4; ++i) {
            const auto &c = coeffs_[i];
            auto &s = states_[i];
            // Direct Form II Transposed:
            // y[n] = b0 * x[n] + s1[n-1]
            // s1[n] = b1 * x[n] - a1 * y[n] + s2[n-1]
            // s2[n] = b2 * x[n] - a2 * y[n]
            const float y = c.b0 * sample + s.s1;
            s.s1 = c.b1 * sample - c.a1 * y + s.s2;
            s.s2 = c.b2 * sample - c.a2 * y;
            sample = std::isfinite(y) ? y : 0.0F;
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
        for (auto &s : states_) {
            s.s1 = 0.0F;
            s.s2 = 0.0F;
        }
    }

private:
    struct BiquadCoeffs {
        float b0 {1.0F};
        float b1 {0.0F};
        float b2 {0.0F};
        float a1 {0.0F};
        float a2 {0.0F};
    };

    struct BiquadState {
        float s1 {0.0F};
        float s2 {0.0F};
    };

    void InitializeDefaultBands() noexcept
    {
        // 4 Studio Vocal Presets: natural warm presence without boosting high-frequency hiss
        bands_[0] = {FilterType::LowShelf, 120.0F, 1.0F, 0.707F};
        bands_[1] = {FilterType::Peaking, 1200.0F, -1.0F, 1.0F};
        bands_[2] = {FilterType::Peaking, 3200.0F, 1.0F, 1.0F};
        bands_[3] = {FilterType::HighShelf, 9000.0F, 0.0F, 0.707F};
    }

    void UpdateCoefficients() noexcept
    {
        for (std::size_t i = 0; i < 4; ++i) {
            ComputeBandCoefficients(i);
        }
    }

    void ComputeBandCoefficients(std::size_t i) noexcept
    {
        constexpr double kPi = 3.14159265358979323846;
        const auto &b = bands_[i];
        const double w0 = 2.0 * kPi * static_cast<double>(b.frequencyHz) / static_cast<double>(sampleRate_);
        const double cosw0 = std::cos(w0);
        const double sinw0 = std::sin(w0);
        const double A = std::pow(10.0, static_cast<double>(b.gainDb) / 40.0);
        const double alpha = sinw0 / (2.0 * static_cast<double>(b.q));

        double b0 = 1.0;
        double b1 = 0.0;
        double b2 = 0.0;
        double a0 = 1.0;
        double a1 = 0.0;
        double a2 = 0.0;

        switch (b.type) {
            case FilterType::Peaking: {
                b0 = 1.0 + alpha * A;
                b1 = -2.0 * cosw0;
                b2 = 1.0 - alpha * A;
                a0 = 1.0 + alpha / A;
                a1 = -2.0 * cosw0;
                a2 = 1.0 - alpha / A;
                break;
            }
            case FilterType::LowShelf: {
                const double twoSqrtAAlpha = 2.0 * std::sqrt(A) * alpha;
                b0 = A * ((A + 1.0) - (A - 1.0) * cosw0 + twoSqrtAAlpha);
                b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosw0);
                b2 = A * ((A + 1.0) - (A - 1.0) * cosw0 - twoSqrtAAlpha);
                a0 = (A + 1.0) + (A - 1.0) * cosw0 + twoSqrtAAlpha;
                a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosw0);
                a2 = (A + 1.0) + (A - 1.0) * cosw0 - twoSqrtAAlpha;
                break;
            }
            case FilterType::HighShelf: {
                const double twoSqrtAAlpha = 2.0 * std::sqrt(A) * alpha;
                b0 = A * ((A + 1.0) + (A - 1.0) * cosw0 + twoSqrtAAlpha);
                b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosw0);
                b2 = A * ((A + 1.0) + (A - 1.0) * cosw0 - twoSqrtAAlpha);
                a0 = (A + 1.0) - (A - 1.0) * cosw0 + twoSqrtAAlpha;
                a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosw0);
                a2 = (A + 1.0) - (A - 1.0) * cosw0 - twoSqrtAAlpha;
                break;
            }
        }

        const double invA0 = (std::fabs(a0) > 1e-9) ? (1.0 / a0) : 1.0;
        coeffs_[i].b0 = static_cast<float>(b0 * invA0);
        coeffs_[i].b1 = static_cast<float>(b1 * invA0);
        coeffs_[i].b2 = static_cast<float>(b2 * invA0);
        coeffs_[i].a1 = static_cast<float>(a1 * invA0);
        coeffs_[i].a2 = static_cast<float>(a2 * invA0);
    }

    uint32_t sampleRate_ {48000};
    bool enabled_ {true};
    std::array<BandConfig, 4> bands_ {};
    std::array<BiquadCoeffs, 4> coeffs_ {};
    std::array<BiquadState, 4> states_ {};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_PARAMETRIC_EQ_H
