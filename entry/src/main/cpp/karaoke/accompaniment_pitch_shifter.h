#ifndef PIVOMIC_KARAOKE_ACCOMPANIMENT_PITCH_SHIFTER_H
#define PIVOMIC_KARAOKE_ACCOMPANIMENT_PITCH_SHIFTER_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace karaoke {

/**
 * @brief Real-time High-Quality Accompaniment Pitch Shifter (Key Transpose: -6 to +6 semitones).
 *
 * Implements dual-tap modulated delay line crossfading with Hann windowing for real-time
 * zero-latency accompaniment key modification without changing tempo.
 */
class AccompanimentPitchShifter final {
public:
    static constexpr std::size_t kWindowSize = 2048; // ~42.6ms window @ 48kHz

    explicit AccompanimentPitchShifter(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
          bufferLeft_(kWindowSize * 2, 0.0F),
          bufferRight_(kWindowSize * 2, 0.0F)
    {
        Reset();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        Reset();
    }

    /**
     * @brief Set Key Transpose in semitones (range: -6 to +6).
     */
    void SetSemitones(float semitones) noexcept
    {
        semitones_ = std::clamp(semitones, -6.0F, 6.0F);
        if (std::fabs(semitones_) < 0.01F) {
            pitchRatio_ = 1.0F;
            isBypassed_ = true;
        } else {
            pitchRatio_ = std::pow(2.0F, semitones_ / 12.0F);
            isBypassed_ = false;
        }
    }

    [[nodiscard]] float Semitones() const noexcept { return semitones_; }
    [[nodiscard]] bool IsBypassed() const noexcept { return isBypassed_; }

    /**
     * @brief Process stereo interleaved PCM samples from input to output buffer.
     */
    void ProcessStereo(const float* input, float* output, std::size_t frames) noexcept
    {
        if (input == nullptr || output == nullptr || frames == 0) return;
        if (isBypassed_) {
            std::copy(input, input + frames * 2, output);
            return;
        }
        std::copy(input, input + frames * 2, output);
        ProcessStereo(output, frames);
    }

    /**
     * @brief Process stereo interleaved PCM samples in-place.
     */
    void ProcessStereo(float* stereoInOut, std::size_t frames) noexcept
    {
        if (stereoInOut == nullptr || frames == 0) return;
        if (isBypassed_) return;

        const auto bufSize = bufferLeft_.size();
        const float windowF = static_cast<float>(kWindowSize);
        const float rate = 1.0F - pitchRatio_;

        for (std::size_t i = 0; i < frames; ++i) {
            const float inL = stereoInOut[i * 2];
            const float inR = stereoInOut[i * 2 + 1];

            bufferLeft_[writePos_] = inL;
            bufferRight_[writePos_] = inR;

            // Modulated tap A
            const float tapA = modPhaseA_;
            // Modulated tap B (180 deg offset)
            const float tapB = std::fmod(modPhaseA_ + windowF * 0.5F, windowF);

            // Hann / Triangular crossfade weights
            const float normA = tapA / windowF;
            const float weightA = 0.5F * (1.0F - std::cos(2.0F * M_PI * normA));
            const float weightB = 1.0F - weightA;

            // Interpolated read tap A
            const float readIdxA = static_cast<float>(writePos_ + 2 * bufSize - 1) - tapA;
            const auto idxA0 = static_cast<std::size_t>(readIdxA) % bufSize;
            const auto idxA1 = (idxA0 + 1) % bufSize;
            const float fracA = readIdxA - std::floor(readIdxA);

            const float outAL = bufferLeft_[idxA0] * (1.0F - fracA) + bufferLeft_[idxA1] * fracA;
            const float outAR = bufferRight_[idxA0] * (1.0F - fracA) + bufferRight_[idxA1] * fracA;

            // Interpolated read tap B
            const float readIdxB = static_cast<float>(writePos_ + 2 * bufSize - 1) - tapB;
            const auto idxB0 = static_cast<std::size_t>(readIdxB) % bufSize;
            const auto idxB1 = (idxB0 + 1) % bufSize;
            const float fracB = readIdxB - std::floor(readIdxB);

            const float outBL = bufferLeft_[idxB0] * (1.0F - fracB) + bufferLeft_[idxB1] * fracB;
            const float outBR = bufferRight_[idxB0] * (1.0F - fracB) + bufferRight_[idxB1] * fracB;

            // Sum crossfaded outputs
            stereoInOut[i * 2] = outAL * weightA + outBL * weightB;
            stereoInOut[i * 2 + 1] = outAR * weightA + outBR * weightB;

            // Advance write pos
            writePos_ = (writePos_ + 1) % bufSize;

            // Advance modulation phase
            modPhaseA_ += rate;
            while (modPhaseA_ >= windowF) modPhaseA_ -= windowF;
            while (modPhaseA_ < 0.0F) modPhaseA_ += windowF;
        }
    }

    void Reset() noexcept
    {
        std::fill(bufferLeft_.begin(), bufferLeft_.end(), 0.0F);
        std::fill(bufferRight_.begin(), bufferRight_.end(), 0.0F);
        writePos_ = 0;
        modPhaseA_ = 0.0F;
    }

private:
    uint32_t sampleRate_ {48000};
    float semitones_ {0.0F};
    float pitchRatio_ {1.0F};
    bool isBypassed_ {true};

    std::vector<float> bufferLeft_;
    std::vector<float> bufferRight_;
    std::size_t writePos_ {0};
    float modPhaseA_ {0.0F};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_ACCOMPANIMENT_PITCH_SHIFTER_H
