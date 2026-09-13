#include "karaoke/acoustic_delay_estimator.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace {

void Check(bool condition, int line)
{
    if (!condition) {
        std::fprintf(stderr, "check failed at line %d\n", line);
        std::abort();
    }
}

} // namespace

#define CHECK(condition) Check((condition), __LINE__)

int main()
{
    karaoke::AcousticDelayEstimator estimator(48000);

    constexpr std::size_t kTestFrames = 48000; // 1 second
    constexpr std::size_t kKnownDelay = 960;   // 20 ms delay @ 48kHz

    std::vector<float> ref(kTestFrames);
    std::vector<float> mic(kTestFrames, 0.0F);

    // Generate broadband pseudo-random noise (LFSR / xorshift)
    uint32_t state = 123456789;
    for (std::size_t i = 0; i < kTestFrames; ++i) {
        state ^= (state << 13);
        state ^= (state >> 17);
        state ^= (state << 5);
        const float noise = static_cast<float>(static_cast<int32_t>(state)) / 2147483648.0F;
        ref[i] = noise * 0.5F;
        if (i >= kKnownDelay) {
            mic[i] = ref[i - kKnownDelay] * 0.7F; // Echo with attenuation
        }
    }

    // Process in blocks of 240 frames (5ms)
    constexpr std::size_t kBlock = 240;
    for (std::size_t offset = 0; offset < kTestFrames; offset += kBlock) {
        estimator.ProcessBlock(ref.data() + offset, false, mic.data() + offset, kBlock);
    }

    const std::size_t estimatedDelay = estimator.EstimatedDelaySamples();
    std::printf("Estimated delay: %zu (target: %zu), confidence: %f\n",
                estimatedDelay, kKnownDelay, estimator.Confidence());

    CHECK(estimator.Confidence() > 0.5F);
    // Should be close to 960 (within downsample accuracy +-32 samples)
    CHECK(estimatedDelay >= kKnownDelay - 64 && estimatedDelay <= kKnownDelay + 64);

    return 0;
}
