#ifndef PIVOMIC_KARAOKE_ACCOMPANIMENT_REFERENCE_RING_H
#define PIVOMIC_KARAOKE_ACCOMPANIMENT_REFERENCE_RING_H

#include "spsc_audio_ring.h"

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>

namespace karaoke {

/**
 * @brief Thread-safe, lock-free ring buffer for Accompaniment Reference signals used in Acoustic Echo Cancellation.
 *
 * Provides a clean abstraction to capture the stereo reference PCM currently rendering on the output DAC,
 * enabling precise time-aligned echo subtraction from microphone input.
 */
class AccompanimentReferenceRing final {
public:
    explicit AccompanimentReferenceRing(std::size_t capacityFrames = 48000 * 2)
        : ring_(capacityFrames * 2) // 2 channels per frame
    {
    }

    /**
     * @brief Write stereo accompaniment frames into the reference ring (Called by AudioRenderer write thread).
     */
    std::size_t WriteReferenceStereo(const int16_t *stereoSamples, std::size_t sampleCount) noexcept
    {
        if (stereoSamples == nullptr || sampleCount == 0) {
            return 0;
        }
        totalFramesWritten_.fetch_add(sampleCount / 2, std::memory_order_relaxed);
        return ring_.Write(stereoSamples, sampleCount);
    }

    /**
     * @brief Read aligned stereo reference frames for AEC cancellation (Called by AEC/DSP thread).
     */
    std::size_t ReadReferenceStereo(int16_t *destStereo, std::size_t sampleCount) noexcept
    {
        if (destStereo == nullptr || sampleCount == 0) {
            return 0;
        }
        return ring_.Read(destStereo, sampleCount);
    }

    [[nodiscard]] std::size_t AvailableSamples() const noexcept
    {
        return ring_.Readable();
    }

    [[nodiscard]] std::uint64_t TotalFramesWritten() const noexcept
    {
        return totalFramesWritten_.load(std::memory_order_relaxed);
    }

    void Clear() noexcept
    {
        ring_.Clear();
        totalFramesWritten_.store(0, std::memory_order_relaxed);
    }

private:
    SpscAudioRing<int16_t> ring_;
    std::atomic<std::uint64_t> totalFramesWritten_ {0};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_ACCOMPANIMENT_REFERENCE_RING_H
