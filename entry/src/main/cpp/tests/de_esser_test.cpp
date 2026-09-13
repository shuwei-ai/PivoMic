#include "karaoke/de_esser.h"

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
    karaoke::DeEsser deEsser(48000);
    deEsser.SetThresholdDb(-20.0F); // linear ~0.1

    constexpr float kPi = 3.14159265358979323846F;

    // 1. Low frequency (500 Hz, fundamental vocal) is untouched
    float lowFreqInPeak = 0.0F;
    float lowFreqOutPeak = 0.0F;
    for (int i = 0; i < 500; ++i) {
        const float x = 0.5F * std::sin(2.0F * kPi * 500.0F * static_cast<float>(i) / 48000.0F);
        const float y = deEsser.ProcessSample(x);
        if (i > 200) {
            lowFreqInPeak = std::max(lowFreqInPeak, std::fabs(x));
            lowFreqOutPeak = std::max(lowFreqOutPeak, std::fabs(y));
        }
    }
    CHECK(std::fabs(lowFreqInPeak - lowFreqOutPeak) < 0.02F);

    // 2. High level 6 kHz sibilance burst is actively attenuated
    deEsser.Reset();
    float sibilanceInPeak = 0.0F;
    float sibilanceOutPeak = 0.0F;
    for (int i = 0; i < 500; ++i) {
        const float x = 0.6F * std::sin(2.0F * kPi * 6000.0F * static_cast<float>(i) / 48000.0F);
        const float y = deEsser.ProcessSample(x);
        if (i > 200) {
            sibilanceInPeak = std::max(sibilanceInPeak, std::fabs(x));
            sibilanceOutPeak = std::max(sibilanceOutPeak, std::fabs(y));
        }
    }
    CHECK(sibilanceInPeak > 0.55F);
    CHECK(sibilanceOutPeak < sibilanceInPeak * 0.75F);

    return 0;
}
