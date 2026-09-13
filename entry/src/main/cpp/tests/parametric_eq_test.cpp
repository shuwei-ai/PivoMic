#include "karaoke/parametric_eq.h"

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
    karaoke::ParametricEQ eq(48000);

    // 1. Pass-through when all gains are 0 dB
    for (std::size_t i = 0; i < 4; ++i) {
        eq.SetBandGain(i, 0.0F);
    }
    constexpr float kPi = 3.14159265358979323846F;
    float peakIn = 0.0F;
    float peakOut = 0.0F;
    for (int i = 0; i < 500; ++i) {
        const float x = std::sin(2.0F * kPi * 1000.0F * static_cast<float>(i) / 48000.0F);
        const float y = eq.ProcessSample(x);
        if (i > 100) {
            peakIn = std::max(peakIn, std::fabs(x));
            peakOut = std::max(peakOut, std::fabs(y));
        }
    }
    CHECK(std::fabs(peakIn - peakOut) < 0.01F);

    // 2. High boost at 3.5kHz boosts 3.5kHz tone
    eq.Reset();
    eq.SetBand(2, karaoke::ParametricEQ::FilterType::Peaking, 3500.0F, 6.0F, 2.0F); // +6dB
    float peak3500 = 0.0F;
    for (int i = 0; i < 500; ++i) {
        const float x = std::sin(2.0F * kPi * 3500.0F * static_cast<float>(i) / 48000.0F);
        const float y = eq.ProcessSample(x);
        if (i > 200) {
            peak3500 = std::max(peak3500, std::fabs(y));
        }
    }
    // +6dB is ~2.0x amplitude
    CHECK(peak3500 > 1.8F && peak3500 < 2.2F);

    // 3. Reset clears state
    eq.Reset();
    CHECK(eq.ProcessSample(0.0F) == 0.0F);

    return 0;
}
