#ifndef PIVOMIC_KARAOKE_ACOUSTIC_ECHO_CANCELLER_H
#define PIVOMIC_KARAOKE_ACOUSTIC_ECHO_CANCELLER_H

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace karaoke {

/**
 * @brief High-performance Linear Acoustic Echo Canceller (Music-AEC) for No-Mic Karaoke.
 *
 * Employs a Normalized Least Mean Squares (NLMS) adaptive filter with:
 * 1. Internal reference delay line for physical speaker-to-mic propagation compensation.
 * 2. Energy-ratio Double-Talk Detector (DTD) to freeze weight adaptation during singing.
 * 3. Music-optimized soft Non-Linear Processor (NLP) that avoids choppy speech cuts / word swallowing.
 * 4. Real-time Echo Return Loss Enhancement (ERLE) metric tracking.
 */
class AcousticEchoCanceller final {
public:
    // Keep the adaptive tail bounded for the 5 ms OHAudio FAST callback. The
    // former 512-tap two-pass NLMS could not finish in real time on device.
    static constexpr std::size_t kFilterTaps = 128;          // ~2.7ms tail length @ 48kHz
    static constexpr std::size_t kMaxDelaySamples = 4800;    // Up to 100ms delay line

    explicit AcousticEchoCanceller(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
          refDelayLine_(kMaxDelaySamples + kFilterTaps + 128, 0.0F),
          weights_(kFilterTaps, 0.0F)
    {
        Reset();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        Reset();
    }

    void SetAlignmentDelay(std::size_t delaySamples) noexcept
    {
        alignmentDelay_ = std::min(delaySamples, kMaxDelaySamples);
    }

    [[nodiscard]] std::size_t AlignmentDelay() const noexcept
    {
        return alignmentDelay_;
    }

    void SetEnabled(bool enabled) noexcept { enabled_ = enabled; }
    [[nodiscard]] bool IsEnabled() const noexcept { return enabled_; }

    [[nodiscard]] float CurrentErleDb() const noexcept
    {
        return erleDb_;
    }

    [[nodiscard]] bool IsDoubleTalk() const noexcept
    {
        return isDoubleTalk_;
    }

    /**
     * @brief Process a single frame of mic input and accompaniment reference.
     * @param micInput Mono microphone input sample d(n) = vocal(n) + echo(n).
     * @param refInput Stereo or mono reference sample x(n).
     * @return Cleaned vocal mono sample e(n) with accompaniment echo subtracted.
     */
    [[nodiscard]] float ProcessSample(float micInput, float refInput) noexcept
    {
        if (!enabled_ || !std::isfinite(micInput)) {
            return micInput;
        }

        refInput = std::isfinite(refInput) ? refInput : 0.0F;

        // 1. Write reference sample into circular delay line
        refDelayLine_[refWritePos_] = refInput;
        refWritePos_ = (refWritePos_ + 1) % refDelayLine_.size();

        // 2. Compute linear echo estimate y_hat = sum(w_k * x(n - D - k))
        float echoEstimate = 0.0F;
        float refNormSq = 0.0F;

        // Base read index with alignment delay
        const std::size_t bufSize = refDelayLine_.size();
        const std::size_t baseIdx = (refWritePos_ + 2 * bufSize - 1 - alignmentDelay_) % bufSize;

        for (std::size_t k = 0; k < kFilterTaps; ++k) {
            const std::size_t idx = (baseIdx + bufSize - k) % bufSize;
            const float x = refDelayLine_[idx];
            echoEstimate += weights_[k] * x;
            refNormSq += x * x;
        }

        // 3. Linear error signal: e = d - y_hat
        const float error = micInput - echoEstimate;

        // 4. Energy tracking & Double Talk Detection (DTD) with Hangover
        const float micSq = micInput * micInput;
        const float errSq = error * error;
        const float refSq = refInput * refInput;

        micPower_ += 0.005F * (micSq - micPower_);
        errPower_ += 0.005F * (errSq - errPower_);
        echoPower_ += 0.005F * (echoEstimate * echoEstimate - echoPower_);
        refPower_ += 0.005F * (refSq - refPower_);

        // Double talk: mic energy significantly exceeds max possible acoustic coupling of reference
        const bool doubleTalkInstant = (micPower_ > refPower_ * 1.8F + 0.02F);
        if (doubleTalkInstant) {
            dtdHangover_ = kDtdHangoverSamples_;
        }

        if (dtdHangover_ > 0) {
            --dtdHangover_;
            isDoubleTalk_ = true;
        } else {
            isDoubleTalk_ = false;
        }

        // 5. Adaptive weight update (Normalized LMS with leakage & clamping)
        // Freeze or strongly slow down adaptation during double-talk to protect filter from vocal corruption
        const float stepSize = isDoubleTalk_ ? 0.0F : 0.05F;
        if (stepSize > 0.0F && refNormSq > 1e-4F) {
            const float normFactor = stepSize / (refNormSq + 1e-3F);
            const float updateTerm = error * normFactor;

            for (std::size_t k = 0; k < kFilterTaps; ++k) {
                const std::size_t idx = (baseIdx + bufSize - k) % bufSize;
                // Leakage is applied per sample. 0.9998 discarded roughly 99.99% of
                // the learned room response every second at 48 kHz, preventing
                // convergence even for a stationary echo path.
                const float updated = weights_[k] * 0.9999999F + updateTerm * refDelayLine_[idx];
                weights_[k] = std::max(-1.0F, std::min(1.0F, updated));
            }
        }

        // 6. Update ERLE (Echo Return Loss Enhancement) metric: ERLE = 10 * log10(P_mic / P_err)
        if (micPower_ > 1e-5F && errPower_ > 1e-6F) {
            const float ratio = micPower_ / errPower_;
            erleDb_ = 10.0F * std::log10(std::max(1.0F, ratio));
        }

        // 7. Gentle Music Non-Linear Processor (NLP)
        // In double-talk singing, return full linear error (100% vocal transparency).
        // In single-talk, suppress un-cancelled residual by max 12dB.
        float output = error;
        if (!isDoubleTalk_ && echoPower_ > 0.001F) {
            constexpr float kGentleSuppression = 0.5F; // 6dB gentle residual suppression
            output = error * kGentleSuppression;
        }

        return output;
    }

    void Process(const float *micMonoIn, const float *refStereoOrMonoIn, bool refIsStereo,
                 float *cleanMonoOut, std::size_t frames) noexcept
    {
        if (micMonoIn == nullptr || cleanMonoOut == nullptr || frames == 0) {
            return;
        }
        for (std::size_t i = 0; i < frames; ++i) {
            const float ref = (refStereoOrMonoIn == nullptr) ? 0.0F :
                (refIsStereo ? (refStereoOrMonoIn[i * 2] + refStereoOrMonoIn[i * 2 + 1]) * 0.5F
                             : refStereoOrMonoIn[i]);
            cleanMonoOut[i] = ProcessSample(micMonoIn[i], ref);
        }
    }

    void Reset() noexcept
    {
        std::fill(refDelayLine_.begin(), refDelayLine_.end(), 0.0F);
        std::fill(weights_.begin(), weights_.end(), 0.0F);
        refWritePos_ = 0;
        micPower_ = 0.0F;
        errPower_ = 0.0F;
        echoPower_ = 0.0F;
        refPower_ = 0.0F;
        erleDb_ = 0.0F;
        isDoubleTalk_ = false;
        dtdHangover_ = 0;
    }

private:
    static constexpr uint32_t kDtdHangoverSamples_ = 2400; // 50ms hangover @ 48kHz

    uint32_t sampleRate_ {48000};
    bool enabled_ {true};
    std::size_t alignmentDelay_ {0};

    std::vector<float> refDelayLine_;
    std::size_t refWritePos_ {0};
    std::vector<float> weights_;

    float micPower_ {0.0F};
    float errPower_ {0.0F};
    float echoPower_ {0.0F};
    float refPower_ {0.0F};
    float erleDb_ {0.0F};
    bool isDoubleTalk_ {false};
    uint32_t dtdHangover_ {0};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_ACOUSTIC_ECHO_CANCELLER_H
