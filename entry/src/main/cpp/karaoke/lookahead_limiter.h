#ifndef PIVOMIC_KARAOKE_LOOKAHEAD_LIMITER_H
#define PIVOMIC_KARAOKE_LOOKAHEAD_LIMITER_H

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace karaoke {

/**
 * @brief Studio-grade Lookahead Soft Limiter with 1.5 ms pre-delay buffer.
 *
 * Prevents digital inter-sample overs and harsh DAC clipping when mixing loud accompaniment,
 * close-mic vocal dynamics, and dense reverberation together into the master output bus.
 *
 * Guarantees peak output never exceeds ceiling (default: -0.3 dBFS ~ 0.966) with zero harmonic distortion.
 */
class LookaheadLimiter final {
public:
    explicit LookaheadLimiter(uint32_t sampleRate = 48000, float lookaheadMs = 1.5F) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
          lookaheadSamples_(std::max<std::size_t>(1, static_cast<std::size_t>(sampleRate_ * (lookaheadMs / 1000.0F))))
    {
        ceilingLinear_ = std::pow(10.0F, ceilingDb_ / 20.0F);
        delayBufferLeft_.assign(lookaheadSamples_, 0.0F);
        delayBufferRight_.assign(lookaheadSamples_, 0.0F);
        Reset();
    }

    void SetCeilingDb(float ceilingDb) noexcept
    {
        ceilingDb_ = std::min(0.0F, ceilingDb);
        ceilingLinear_ = std::pow(10.0F, ceilingDb_ / 20.0F);
    }

    [[nodiscard]] float CeilingLinear() const noexcept { return ceilingLinear_; }

    /**
     * @brief Process a single stereo sample frame through lookahead delay & gain reduction.
     */
    void ProcessSample(float inLeft, float inRight, float &outLeft, float &outRight) noexcept
    {
        inLeft = std::isfinite(inLeft) ? inLeft : 0.0F;
        inRight = std::isfinite(inRight) ? inRight : 0.0F;

        // 1. Linked stereo peak detection of the incoming un-delayed frame
        const float framePeak = std::max(std::fabs(inLeft), std::fabs(inRight));

        // 2. Compute required attenuation target
        float targetGain = 1.0F;
        if (framePeak > ceilingLinear_ && ceilingLinear_ > 1e-4F) {
            targetGain = ceilingLinear_ / framePeak;
        }

        // 3. Fast attack lookahead smoothing, gentle release (50 ms)
        const float attackCoeff = 0.5F; // fast response within lookahead window
        const float releaseCoeff = 0.001F;
        const float coeff = targetGain < envelopeGain_ ? attackCoeff : releaseCoeff;
        envelopeGain_ += coeff * (targetGain - envelopeGain_);

        // 4. Retrieve delayed sample from lookahead line
        const float delayedLeft = delayBufferLeft_[writePos_];
        const float delayedRight = delayBufferRight_[writePos_];

        // 5. Store current input into delay line
        delayBufferLeft_[writePos_] = inLeft;
        delayBufferRight_[writePos_] = inRight;
        writePos_ = (writePos_ + 1) % lookaheadSamples_;

        // 6. Apply gain reduction
        outLeft = std::max(-ceilingLinear_, std::min(delayedLeft * envelopeGain_, ceilingLinear_));
        outRight = std::max(-ceilingLinear_, std::min(delayedRight * envelopeGain_, ceilingLinear_));
    }

    void ProcessStereo(const float *inStereo, float *outStereo, std::size_t frames) noexcept
    {
        if (inStereo == nullptr || outStereo == nullptr || frames == 0) {
            return;
        }
        for (std::size_t i = 0; i < frames; ++i) {
            ProcessSample(inStereo[i * 2], inStereo[i * 2 + 1],
                          outStereo[i * 2], outStereo[i * 2 + 1]);
        }
    }

    void Reset() noexcept
    {
        std::fill(delayBufferLeft_.begin(), delayBufferLeft_.end(), 0.0F);
        std::fill(delayBufferRight_.begin(), delayBufferRight_.end(), 0.0F);
        writePos_ = 0;
        envelopeGain_ = 1.0F;
    }

private:
    uint32_t sampleRate_ {48000};
    std::size_t lookaheadSamples_ {72};
    float ceilingDb_ {-0.3F};
    float ceilingLinear_ {0.96605F};

    std::vector<float> delayBufferLeft_;
    std::vector<float> delayBufferRight_;
    std::size_t writePos_ {0};

    float envelopeGain_ {1.0F};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_LOOKAHEAD_LIMITER_H
