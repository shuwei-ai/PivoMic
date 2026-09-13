#ifndef PIVOMIC_KARAOKE_SPSC_AUDIO_RING_H
#define PIVOMIC_KARAOKE_SPSC_AUDIO_RING_H

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <type_traits>
#include <vector>

namespace karaoke {

// A bounded single-producer/single-consumer ring. The requested capacity is
// rounded up to a power of two; Capacity() reports the resulting capacity.
// Write/Writable belong to the producer, Read/Readable/Discard/Clear to the consumer.
// Clear must not run concurrently with another consumer operation.
template<typename T>
class SpscAudioRing final {
    static_assert(!std::is_const_v<T> && !std::is_volatile_v<T>,
        "audio ring elements must not be cv-qualified");
    static_assert(std::is_default_constructible_v<T>,
        "audio ring elements must be default constructible");
    static_assert(std::is_trivially_copyable_v<T>, "audio ring elements must be trivially copyable");

public:
    explicit SpscAudioRing(std::size_t requestedCapacity)
        : capacity_(NormalizeCapacity(requestedCapacity)), mask_(capacity_ - 1), storage_(capacity_)
    {
    }

    SpscAudioRing(const SpscAudioRing&) = delete;
    SpscAudioRing& operator=(const SpscAudioRing&) = delete;

    std::size_t Capacity() const noexcept
    {
        return capacity_;
    }

    std::size_t Readable() const noexcept
    {
        const Cursor read = readCursor_.load(std::memory_order_relaxed);
        const Cursor write = writeCursor_.load(std::memory_order_acquire);
        return static_cast<std::size_t>(write - read);
    }

    std::size_t Writable() const noexcept
    {
        const Cursor write = writeCursor_.load(std::memory_order_relaxed);
        const Cursor read = readCursor_.load(std::memory_order_acquire);
        return capacity_ - static_cast<std::size_t>(write - read);
    }

    std::size_t Write(const T* source, std::size_t count) noexcept
    {
        const Cursor write = writeCursor_.load(std::memory_order_relaxed);
        const Cursor read = readCursor_.load(std::memory_order_acquire);
        const std::size_t available = capacity_ - static_cast<std::size_t>(write - read);
        const std::size_t written = std::min(count, available);
        CopyInto(write, source, written);
        writeCursor_.store(write + written, std::memory_order_release);
        return written;
    }

    std::size_t Read(T* destination, std::size_t count) noexcept
    {
        const Cursor read = readCursor_.load(std::memory_order_relaxed);
        const Cursor write = writeCursor_.load(std::memory_order_acquire);
        const std::size_t available = static_cast<std::size_t>(write - read);
        const std::size_t readCount = std::min(count, available);
        CopyOut(read, destination, readCount);
        readCursor_.store(read + readCount, std::memory_order_release);
        return readCount;
    }

    // Consumer-only: advance without copying. The producer never owns readCursor_.
    std::size_t Discard(std::size_t count) noexcept
    {
        const Cursor read = readCursor_.load(std::memory_order_relaxed);
        const Cursor write = writeCursor_.load(std::memory_order_acquire);
        const std::size_t discarded = std::min(count, static_cast<std::size_t>(write - read));
        readCursor_.store(read + discarded, std::memory_order_release);
        return discarded;
    }

    void Clear() noexcept
    {
        const Cursor write = writeCursor_.load(std::memory_order_acquire);
        readCursor_.store(write, std::memory_order_release);
    }

private:
    using Cursor = std::uint64_t;

    static std::size_t NormalizeCapacity(std::size_t requested)
    {
        constexpr std::size_t kMaximum =
            std::size_t {1} << (std::numeric_limits<std::size_t>::digits - 1);
        if (requested == 0 || requested > kMaximum) {
            throw std::invalid_argument("ring capacity is out of range");
        }

        std::size_t normalized = 1;
        while (normalized < requested) {
            normalized <<= 1;
        }
        return normalized;
    }

    void CopyInto(Cursor cursor, const T* source, std::size_t count) noexcept
    {
        const std::size_t start = static_cast<std::size_t>(cursor) & mask_;
        const std::size_t first = std::min(count, capacity_ - start);
        if (first != 0) {
            std::memcpy(storage_.data() + start, source, first * sizeof(T));
        }
        if (count != first) {
            std::memcpy(storage_.data(), source + first, (count - first) * sizeof(T));
        }
    }

    void CopyOut(Cursor cursor, T* destination, std::size_t count) const noexcept
    {
        const std::size_t start = static_cast<std::size_t>(cursor) & mask_;
        const std::size_t first = std::min(count, capacity_ - start);
        if (first != 0) {
            std::memcpy(destination, storage_.data() + start, first * sizeof(T));
        }
        if (count != first) {
            std::memcpy(destination + first, storage_.data(), (count - first) * sizeof(T));
        }
    }

    const std::size_t capacity_;
    const std::size_t mask_;
    std::vector<T> storage_;
    alignas(64) std::atomic<Cursor> readCursor_ {0};
    alignas(64) std::atomic<Cursor> writeCursor_ {0};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_SPSC_AUDIO_RING_H
