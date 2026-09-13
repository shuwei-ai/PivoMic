#include "karaoke/spsc_audio_ring.h"
#include "karaoke/microphone_backlog_policy.h"

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <thread>
#include <type_traits>
#include <vector>

namespace {

using IntRing = karaoke::SpscAudioRing<int>;
static_assert(std::is_constructible_v<IntRing, std::size_t>);
static_assert(!std::is_copy_constructible_v<IntRing>);
static_assert(!std::is_copy_assignable_v<IntRing>);

bool Check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
    }
    return condition;
}

#define CHECK(expression)                                                                            \
    do {                                                                                             \
        if (!Check(static_cast<bool>(expression), #expression, __LINE__)) {                         \
            return false;                                                                            \
        }                                                                                            \
    } while (false)

bool TestWraparoundAndClear()
{
    karaoke::SpscAudioRing<int> ring(8);
    const std::array<int, 6> first {1, 2, 3, 4, 5, 6};
    CHECK(ring.Write(first.data(), first.size()) == first.size());

    std::array<int, 4> prefix {};
    CHECK(ring.Read(prefix.data(), prefix.size()) == prefix.size());
    CHECK((prefix == std::array<int, 4> {1, 2, 3, 4}));

    const std::array<int, 6> second {7, 8, 9, 10, 11, 12};
    CHECK(ring.Write(second.data(), second.size()) == second.size());

    std::array<int, 8> remainder {};
    CHECK(ring.Read(remainder.data(), remainder.size()) == remainder.size());
    CHECK((remainder == std::array<int, 8> {5, 6, 7, 8, 9, 10, 11, 12}));
    CHECK(ring.Read(remainder.data(), 1) == 0);

    CHECK(ring.Write(first.data(), first.size()) == first.size());
    ring.Clear();
    CHECK(ring.Readable() == 0);
    CHECK(ring.Writable() == ring.Capacity());
    return true;
}

bool TestBoundedPartialOperations()
{
    karaoke::SpscAudioRing<int> ring(5);
    CHECK(ring.Capacity() == 8);

    const std::array<int, 10> input {0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
    CHECK(ring.Write(input.data(), input.size()) == 8);
    CHECK(ring.Readable() == 8);
    CHECK(ring.Writable() == 0);
    CHECK(ring.Write(input.data(), 1) == 0);

    std::array<int, 12> output {};
    CHECK(ring.Read(output.data(), output.size()) == 8);
    for (std::size_t i = 0; i < 8; ++i) {
        CHECK(output[i] == static_cast<int>(i));
    }
    CHECK(ring.Read(output.data(), 1) == 0);
    return true;
}

bool TestConcurrentTransfer()
{
    constexpr std::uint32_t kItemCount = 1'000'000;
    karaoke::SpscAudioRing<std::uint32_t> ring(1024);
    std::atomic<bool> valid {true};

    std::thread producer([&ring] {
        std::uint32_t next = 0;
        while (next < kItemCount) {
            next += static_cast<std::uint32_t>(ring.Write(&next, 1));
        }
    });

    std::thread consumer([&ring, &valid] {
        std::uint32_t expected = 0;
        while (expected < kItemCount) {
            std::uint32_t value = 0;
            if (ring.Read(&value, 1) == 0) {
                continue;
            }
            if (value != expected) {
                valid.store(false, std::memory_order_relaxed);
                return;
            }
            ++expected;
        }
    });

    producer.join();
    consumer.join();
    CHECK(valid.load(std::memory_order_relaxed));
    CHECK(ring.Readable() == 0);
    return true;
}

bool TestMicrophoneRecovery()
{
    karaoke::SpscAudioRing<int> ring(48000 * 4);
    std::vector<int> old(96000, -1);
    std::vector<int> recent(720, 42);
    CHECK(ring.Write(old.data(), old.size()) == old.size());
    CHECK(ring.Write(recent.data(), recent.size()) == recent.size());
    CHECK(karaoke::TrimMicrophoneBacklog(ring, 240) == old.size());
    std::array<int, 240> output {};
    CHECK(ring.Read(output.data(), output.size()) == output.size());
    for (int value : output) CHECK(value == 42);
    // Equal-rate capture/render must stay current after recovery.
    for (int i = 0; i < 500; ++i) {
        CHECK(ring.Write(recent.data(), 240) == 240);
        CHECK(karaoke::TrimMicrophoneBacklog(ring, 240) == 0);
        CHECK(ring.Read(output.data(), output.size()) == output.size());
        for (int value : output) CHECK(value == 42);
    }
    CHECK(ring.Readable() == 480);
    return true;
}

bool TestMicrophoneBatchingAndWraparound()
{
    karaoke::SpscAudioRing<int> ring(4096);
    std::vector<int> input(4096);
    for (std::size_t i = 0; i < input.size(); ++i) input[i] = static_cast<int>(i);
    std::vector<int> output(4096);
    CHECK(karaoke::TrimMicrophoneBacklog(ring, 960) == 0);
    CHECK(ring.Write(input.data(), 2880) == 2880);
    // A whole renderer callback plus 40ms jitter is allowed untouched.
    CHECK(karaoke::TrimMicrophoneBacklog(ring, 960) == 0);
    CHECK(ring.Read(output.data(), 2880) == 2880);
    CHECK(ring.Write(input.data(), input.size()) == input.size());
    CHECK(karaoke::TrimMicrophoneBacklog(ring, 960) == 2656);
    CHECK(ring.Read(output.data(), 1440) == 1440);
    for (std::size_t i = 0; i < 1440; ++i) CHECK(output[i] == static_cast<int>(2656 + i));
    CHECK(ring.Readable() == 0);
    return true;
}

} // namespace

int main()
{
    if (!TestWraparoundAndClear() || !TestBoundedPartialOperations() || !TestConcurrentTransfer() ||
        !TestMicrophoneRecovery() || !TestMicrophoneBatchingAndWraparound()) {
        return 1;
    }
    return 0;
}
