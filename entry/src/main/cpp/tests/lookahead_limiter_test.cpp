#include "karaoke/lookahead_limiter.h"

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
    karaoke::LookaheadLimiter limiter(48000, 1.5F);
    const float ceiling = limiter.CeilingLinear();
    CHECK(ceiling > 0.95F && ceiling <= 1.0F);

    // 1. Signals below ceiling pass through cleanly after lookahead delay
    constexpr float kPi = 3.14159265358979323846F;
    float peakOut = 0.0F;
    for (int i = 0; i < 500; ++i) {
        const float x = 0.5F * std::sin(2.0F * kPi * 1000.0F * static_cast<float>(i) / 48000.0F);
        float outL = 0.0F;
        float outR = 0.0F;
        limiter.ProcessSample(x, x, outL, outR);
        if (i > 100) {
            peakOut = std::max(peakOut, std::fabs(outL));
        }
    }
    CHECK(std::fabs(peakOut - 0.5F) < 0.01F);

    // 2. High overload signals (+6 dBFS, amplitude = 2.0) are limited <= ceiling
    limiter.Reset();
    float maxOverloadOut = 0.0F;
    for (int i = 0; i < 1000; ++i) {
        const float x = 2.0F * std::sin(2.0F * kPi * 440.0F * static_cast<float>(i) / 48000.0F);
        float outL = 0.0F;
        float outR = 0.0F;
        limiter.ProcessSample(x, x, outL, outR);
        maxOverloadOut = std::max(maxOverloadOut, std::fabs(outL));
    }
    CHECK(maxOverloadOut <= ceiling + 1e-4F);
    CHECK(maxOverloadOut > 0.85F);

    return 0;
}
