#ifndef PIVOMIC_KARAOKE_SPATIAL_REVERB_H
#define PIVOMIC_KARAOKE_SPATIAL_REVERB_H

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace karaoke {

/**
 * @brief Industry-standard Freeverb (Schroeder-Moorer) Studio Reverb Engine.
 *
 * Architecture:
 * - 8 Parallel Lowpass Feedback Comb Filters (LBCF) per stereo channel.
 * - 4 Cascaded All-Pass Filters (APF) per stereo channel for phase diffusion.
 * - Stereo decorrelation via 23-sample spatial offset.
 * - Built-in Denormal / FTZ protection for ARM NEON DSP.
 */
class SpatialReverb final {
private:
    static constexpr std::size_t kNumCombs = 8;
    static constexpr std::size_t kNumAllpasses = 4;
    static constexpr std::size_t kStereoSpread = 23;

    // Comb filter tuning at 44.1kHz
    static constexpr std::array<int, kNumCombs> kCombTuning = {
        1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617
    };

    // Allpass filter tuning at 44.1kHz
    static constexpr std::array<int, kNumAllpasses> kAllpassTuning = {
        556, 441, 341, 225
    };

    struct CombFilter {
        std::vector<float> buffer;
        std::size_t bufIdx {0};
        float filterStore {0.0F};

        void Init(std::size_t size)
        {
            buffer.assign(std::max<std::size_t>(size, 1), 0.0F);
            bufIdx = 0;
            filterStore = 0.0F;
        }

        [[nodiscard]] inline float Process(float input, float feedback, float damp) noexcept
        {
            const float output = buffer[bufIdx];
            // One-pole lowpass feedback damping with denormal flush
            filterStore = (output * (1.0F - damp)) + (filterStore * damp);
            if (std::fabs(filterStore) < 1e-8F) filterStore = 0.0F;

            const float newBuf = input + (filterStore * feedback);
            buffer[bufIdx] = (std::isfinite(newBuf) && std::fabs(newBuf) >= 1e-8F) ? newBuf : 0.0F;

            bufIdx = (bufIdx + 1) % buffer.size();
            return output;
        }

        void Reset() noexcept
        {
            std::fill(buffer.begin(), buffer.end(), 0.0F);
            bufIdx = 0;
            filterStore = 0.0F;
        }
    };

    struct AllPassFilter {
        std::vector<float> buffer;
        std::size_t bufIdx {0};

        void Init(std::size_t size)
        {
            buffer.assign(std::max<std::size_t>(size, 1), 0.0F);
            bufIdx = 0;
        }

        [[nodiscard]] inline float Process(float input) noexcept
        {
            const float bufOut = buffer[bufIdx];
            const float output = -input + bufOut;
            const float newBuf = input + (bufOut * 0.5F);
            buffer[bufIdx] = (std::isfinite(newBuf) && std::fabs(newBuf) >= 1e-8F) ? newBuf : 0.0F;

            bufIdx = (bufIdx + 1) % buffer.size();
            return output;
        }

        void Reset() noexcept
        {
            std::fill(buffer.begin(), buffer.end(), 0.0F);
            bufIdx = 0;
        }
    };

public:
    explicit SpatialReverb(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate)
    {
        InitializeDelayLines();
        UpdateCoefficients();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        InitializeDelayLines();
        UpdateCoefficients();
    }

    void SetRoomSize(float roomSize) noexcept
    {
        roomSize_ = std::max(0.0F, std::min(roomSize, 1.0F));
        UpdateCoefficients();
    }

    void SetDamping(float damping) noexcept
    {
        damping_ = std::max(0.0F, std::min(damping, 1.0F));
        UpdateCoefficients();
    }

    void SetWidth(float width) noexcept
    {
        width_ = std::max(0.0F, std::min(width, 1.0F));
        UpdateCoefficients();
    }

    /**
     * @brief Process a mono vocal dry input and compute lush stereo Freeverb output.
     */
    void ProcessSample(float input, float &outLeft, float &outRight) noexcept
    {
        if (!std::isfinite(input) || std::fabs(input) < 1e-8F) {
            input = 0.0F;
        }

        // Input gain scaling
        const float scaledIn = input * 0.015F;

        // 1. Parallel Comb Filters (Left & Right)
        float outL = 0.0F;
        float outR = 0.0F;

        for (std::size_t i = 0; i < kNumCombs; ++i) {
            outL += combsL_[i].Process(scaledIn, feedback_, dampVal_);
            outR += combsR_[i].Process(scaledIn, feedback_, dampVal_);
        }

        // 2. Cascaded Allpass Diffusers (Left & Right)
        for (std::size_t i = 0; i < kNumAllpasses; ++i) {
            outL = allpassesL_[i].Process(outL);
            outR = allpassesR_[i].Process(outR);
        }

        // 3. Stereo Spatial Mixing Matrix with Width Expansion
        const float wetL = outL * wet1_ + outR * wet2_;
        const float wetR = outR * wet1_ + outL * wet2_;

        outLeft = std::max(-1.0F, std::min(1.0F, wetL * 2.8F));
        outRight = std::max(-1.0F, std::min(1.0F, wetR * 2.8F));
    }

    void Reset() noexcept
    {
        for (auto &comb : combsL_) comb.Reset();
        for (auto &comb : combsR_) comb.Reset();
        for (auto &ap : allpassesL_) ap.Reset();
        for (auto &ap : allpassesR_) ap.Reset();
    }

private:
    void InitializeDelayLines() noexcept
    {
        const float scale = static_cast<float>(sampleRate_) / 44100.0F;
        for (std::size_t i = 0; i < kNumCombs; ++i) {
            combsL_[i].Init(static_cast<std::size_t>(kCombTuning[i] * scale));
            combsR_[i].Init(static_cast<std::size_t>((kCombTuning[i] + kStereoSpread) * scale));
        }

        for (std::size_t i = 0; i < kNumAllpasses; ++i) {
            allpassesL_[i].Init(static_cast<std::size_t>(kAllpassTuning[i] * scale));
            allpassesR_[i].Init(static_cast<std::size_t>((kAllpassTuning[i] + kStereoSpread) * scale));
        }

        Reset();
    }

    void UpdateCoefficients() noexcept
    {
        // Freeverb formula: feedback = roomsize * 0.28 + 0.7
        feedback_ = roomSize_ * 0.28F + 0.7F;
        // dampVal = damping * 0.4
        dampVal_ = damping_ * 0.4F;

        // Stereo width coefficients
        wet1_ = 0.5F * (1.0F + width_);
        wet2_ = 0.5F * (1.0F - width_);
    }

    uint32_t sampleRate_ {48000};
    float roomSize_ {0.75F};
    float damping_ {0.35F};
    float width_ {1.0F};

    float feedback_ {0.91F};
    float dampVal_ {0.14F};
    float wet1_ {1.0F};
    float wet2_ {0.0F};

    std::array<CombFilter, kNumCombs> combsL_;
    std::array<CombFilter, kNumCombs> combsR_;
    std::array<AllPassFilter, kNumAllpasses> allpassesL_;
    std::array<AllPassFilter, kNumAllpasses> allpassesR_;
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_SPATIAL_REVERB_H
