#ifndef PIVOMIC_KARAOKE_ACOUSTIC_DELAY_ESTIMATOR_H
#define PIVOMIC_KARAOKE_ACOUSTIC_DELAY_ESTIMATOR_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace karaoke {

/**
 * @brief Fast Acoustic Delay Estimator based on Normalized Cross-Correlation (NCC).
 *
 * Automatically tracks physical propagation delay between speaker DAC output and microphone ADC input
 * (typically 10ms ~ 100ms) to ensure the Acoustic Echo Canceller (AEC) aligns reference frames with mic frames.
 */
class AcousticDelayEstimator final {
public:
    static constexpr std::size_t kMaxDelaySamples = 4800; // Up to 100ms @ 48kHz
    static constexpr std::size_t kDownsampleFactor = 8;    // Downsample to 6kHz for rapid correlation

    explicit AcousticDelayEstimator(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
          refBufferSize_(kMaxDelaySamples / kDownsampleFactor + 256),
          micBufferSize_(256)
    {
        refDownsampled_.assign(refBufferSize_, 0.0F);
        micDownsampled_.assign(micBufferSize_, 0.0F);
        Reset();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        Reset();
    }

    [[nodiscard]] std::size_t EstimatedDelaySamples() const noexcept
    {
        return estimatedDelaySamples_;
    }

    [[nodiscard]] float Confidence() const noexcept
    {
        return confidence_;
    }

    /**
     * @brief Feed synchronous reference (playback) and mic capture sample blocks to update delay estimate.
     */
    void ProcessBlock(const float *refStereoOrMono, bool refIsStereo, const float *micMono, std::size_t frames) noexcept
    {
        if (refStereoOrMono == nullptr || micMono == nullptr || frames == 0) {
            return;
        }

        for (std::size_t i = 0; i < frames; ++i) {
            const float refSample = refIsStereo ? (refStereoOrMono[i * 2] + refStereoOrMono[i * 2 + 1]) * 0.5F
                                                : refStereoOrMono[i];
            const float micSample = micMono[i];

            refAcc_ += refSample;
            micAcc_ += micSample;
            ++decimCounter_;

            if (decimCounter_ >= kDownsampleFactor) {
                const float dsRef = refAcc_ / static_cast<float>(kDownsampleFactor);
                const float dsMic = micAcc_ / static_cast<float>(kDownsampleFactor);
                refAcc_ = 0.0F;
                micAcc_ = 0.0F;
                decimCounter_ = 0;

                PushDownsampled(dsRef, dsMic);
            }
        }
    }

    void Reset() noexcept
    {
        std::fill(refDownsampled_.begin(), refDownsampled_.end(), 0.0F);
        std::fill(micDownsampled_.begin(), micDownsampled_.end(), 0.0F);
        refWritePos_ = 0;
        micWritePos_ = 0;
        decimCounter_ = 0;
        refAcc_ = 0.0F;
        micAcc_ = 0.0F;
        sampleCount_ = 0;
        estimatedDelaySamples_ = 480; // 10ms initial default
        confidence_ = 0.0F;
    }

private:
    void PushDownsampled(float ref, float mic) noexcept
    {
        refDownsampled_[refWritePos_] = ref;
        refWritePos_ = (refWritePos_ + 1) % refBufferSize_;

        micDownsampled_[micWritePos_] = mic;
        micWritePos_ = (micWritePos_ + 1) % micBufferSize_;

        ++sampleCount_;
        // Perform correlation calculation every 128 downsampled points (~21ms)
        if (sampleCount_ >= 128) {
            sampleCount_ = 0;
            ComputeCorrelation();
        }
    }

    void ComputeCorrelation() noexcept
    {
        // Correlation search range in downsampled domain: 0 to kMaxDelaySamples/kDownsampleFactor
        const std::size_t maxLag = kMaxDelaySamples / kDownsampleFactor;
        const std::size_t corrLength = 64; // 64 downsampled points ~ 10.6ms correlation window

        float maxCorr = 0.0F;
        std::size_t bestLag = 0;
        float refEnergySum = 0.0F;
        float micEnergySum = 0.0F;

        for (std::size_t i = 0; i < corrLength; ++i) {
            const std::size_t micIdx = (micWritePos_ + 4 * micBufferSize_ - corrLength + i) % micBufferSize_;
            const float m = micDownsampled_[micIdx];
            micEnergySum += m * m;
        }

        if (micEnergySum < 1e-4F) {
            confidence_ = 0.0F;
            return;
        }

        for (std::size_t lag = 0; lag < maxLag; ++lag) {
            float corr = 0.0F;
            float lagRefEnergy = 0.0F;
            for (std::size_t i = 0; i < corrLength; ++i) {
                const std::size_t micIdx = (micWritePos_ + 4 * micBufferSize_ - corrLength + i) % micBufferSize_;
                const std::size_t refIdx = (refWritePos_ + 4 * refBufferSize_ - corrLength - lag + i) % refBufferSize_;
                const float m = micDownsampled_[micIdx];
                const float r = refDownsampled_[refIdx];
                corr += m * r;
                lagRefEnergy += r * r;
            }

            const float normFactor = std::sqrt(lagRefEnergy * micEnergySum + 1e-6F);
            const float ncc = std::fabs(corr) / normFactor;
            if (ncc > maxCorr) {
                maxCorr = ncc;
                bestLag = lag;
            }
            refEnergySum = std::max(refEnergySum, lagRefEnergy);
        }

        if (maxCorr > 0.4F && refEnergySum > 1e-3F) {
            confidence_ = maxCorr;
            const auto candidateSamples = bestLag * kDownsampleFactor;
            // Smooth delay update
            estimatedDelaySamples_ = static_cast<std::size_t>(
                0.8F * static_cast<float>(estimatedDelaySamples_) + 0.2F * static_cast<float>(candidateSamples));
        } else {
            confidence_ *= 0.9F;
        }
    }

    uint32_t sampleRate_ {48000};
    std::size_t refBufferSize_ {856};
    std::size_t micBufferSize_ {256};

    std::vector<float> refDownsampled_;
    std::vector<float> micDownsampled_;
    std::size_t refWritePos_ {0};
    std::size_t micWritePos_ {0};

    std::size_t decimCounter_ {0};
    float refAcc_ {0.0F};
    float micAcc_ {0.0F};
    std::size_t sampleCount_ {0};

    std::size_t estimatedDelaySamples_ {480};
    float confidence_ {0.0F};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_ACOUSTIC_DELAY_ESTIMATOR_H
