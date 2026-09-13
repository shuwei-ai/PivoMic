#ifndef PIVOMIC_KARAOKE_DUAL_TRACK_RECORDER_H
#define PIVOMIC_KARAOKE_DUAL_TRACK_RECORDER_H

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <vector>

namespace karaoke {

/**
 * @brief High-performance lock-free dual-track recording sink.
 *
 * Captures synchronized:
 * Track A: Clean dry vocal mono PCM (post-AEC & anti-howling, pre-reverb).
 * Track B: Music accompaniment stereo PCM.
 */
class DualTrackRecorder final {
public:
    static constexpr std::size_t kMaxCapacityFrames = 48000 * 60 * 10; // Up to 10 minutes @ 48kHz

    DualTrackRecorder() noexcept
    {
        Reset();
    }

    void StartRecording() noexcept
    {
        recordedFrames_.store(0, std::memory_order_relaxed);
        vocalBuffer_.assign(kMaxCapacityFrames, 0);
        musicBuffer_.assign(kMaxCapacityFrames * 2, 0);
        isRecording_.store(true, std::memory_order_release);
    }

    void StopRecording() noexcept
    {
        isRecording_.store(false, std::memory_order_release);
    }

    [[nodiscard]] bool IsRecording() const noexcept
    {
        return isRecording_.load(std::memory_order_acquire);
    }

    [[nodiscard]] std::size_t RecordedFrames() const noexcept
    {
        return recordedFrames_.load(std::memory_order_acquire);
    }

    [[nodiscard]] int64_t RecordedDurationMs() const noexcept
    {
        return static_cast<int64_t>(RecordedFrames() / 48);
    }

    /**
     * @brief Feed synchronous audio frames from real-time audio callback thread.
     * Zero-alloc, lock-free.
     */
    void PushFrame(const int16_t* vocalDryMono, const int16_t* musicStereo, std::size_t frames) noexcept
    {
        if (!isRecording_.load(std::memory_order_relaxed) || frames == 0) {
            return;
        }

        const std::size_t current = recordedFrames_.load(std::memory_order_relaxed);
        if (current + frames > kMaxCapacityFrames) {
            isRecording_.store(false, std::memory_order_relaxed);
            return;
        }

        if (vocalDryMono != nullptr && current < vocalBuffer_.size()) {
            std::memcpy(&vocalBuffer_[current], vocalDryMono, frames * sizeof(int16_t));
        }

        if (musicStereo != nullptr && (current * 2 + frames * 2) <= musicBuffer_.size()) {
            std::memcpy(&musicBuffer_[current * 2], musicStereo, frames * 2 * sizeof(int16_t));
        }

        recordedFrames_.store(current + frames, std::memory_order_release);
    }

    const std::vector<int16_t>& VocalTrack() const noexcept { return vocalBuffer_; }
    const std::vector<int16_t>& MusicTrack() const noexcept { return musicBuffer_; }

    bool ExportMasterWav(const std::string& outputPath, float vocalGain = 1.2F, float musicGain = 0.8F) const noexcept
    {
        const std::size_t totalFrames = recordedFrames_.load(std::memory_order_acquire);
        if (totalFrames == 0 || outputPath.empty()) return false;

        FILE *f = std::fopen(outputPath.c_str(), "wb");
        if (f == nullptr) return false;

        // 44-byte standard RIFF WAVE header for 48kHz 16-bit Stereo PCM
        struct {
            char riff[4] = {'R', 'I', 'F', 'F'};
            uint32_t fileSize = 0;
            char wave[4] = {'W', 'A', 'V', 'E'};
            char fmt[4] = {'f', 'm', 't', ' '};
            uint32_t fmtSize = 16;
            uint16_t audioFormat = 1; // PCM
            uint16_t numChannels = 2; // Stereo
            uint32_t sampleRate = 48000;
            uint32_t byteRate = 48000 * 2 * sizeof(int16_t);
            uint16_t blockAlign = 2 * sizeof(int16_t);
            uint16_t bitsPerSample = 16;
            char data[4] = {'d', 'a', 't', 'a'};
            uint32_t dataSize = 0;
        } header;

        const uint32_t dataBytes = static_cast<uint32_t>(totalFrames * 2 * sizeof(int16_t));
        header.dataSize = dataBytes;
        header.fileSize = 36 + dataBytes;

        if (std::fwrite(&header, sizeof(header), 1, f) != 1) {
            std::fclose(f);
            return false;
        }

        std::vector<int16_t> mixedChunk(960 * 2); // 20ms chunk
        std::size_t offset = 0;
        while (offset < totalFrames) {
            const std::size_t count = std::min<std::size_t>(960, totalFrames - offset);
            for (std::size_t i = 0; i < count; ++i) {
                const std::size_t frameIdx = offset + i;
                const float vocal = (frameIdx < vocalBuffer_.size() ? vocalBuffer_[frameIdx] : 0) * vocalGain;
                const float musicL = (frameIdx * 2 < musicBuffer_.size() ? musicBuffer_[frameIdx * 2] : 0) * musicGain;
                const float musicR = (frameIdx * 2 + 1 < musicBuffer_.size() ? musicBuffer_[frameIdx * 2 + 1] : 0) * musicGain;

                const float mixL = musicL + vocal;
                const float mixR = musicR + vocal;

                mixedChunk[i * 2] = static_cast<int16_t>(std::max(-32768.0F, std::min(32767.0F, mixL)));
                mixedChunk[i * 2 + 1] = static_cast<int16_t>(std::max(-32768.0F, std::min(32767.0F, mixR)));
            }
            std::fwrite(mixedChunk.data(), sizeof(int16_t), count * 2, f);
            offset += count;
        }

        std::fclose(f);
        return true;
    }

    void Reset() noexcept
    {
        isRecording_.store(false, std::memory_order_relaxed);
        recordedFrames_.store(0, std::memory_order_relaxed);
        vocalBuffer_.clear();
        musicBuffer_.clear();
    }

private:
    std::atomic<bool> isRecording_ {false};
    std::atomic<std::size_t> recordedFrames_ {0};

    std::vector<int16_t> vocalBuffer_;
    std::vector<int16_t> musicBuffer_;
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_DUAL_TRACK_RECORDER_H
