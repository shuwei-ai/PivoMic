#include "karaoke/dynamic_notch_filter.h"

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
    karaoke::DynamicNotchFilter notchFilter(48000);
    notchFilter.SetAutoDetectionEnabled(false); // test explicit filter action first
    constexpr float kPi = 3.14159265358979323846F;

    // 1. Initially no active notches; signal passes through
    CHECK(notchFilter.ActiveNotchCount() == 0);
    float inPeak = 0.0F;
    float outPeak = 0.0F;
    for (int i = 0; i < 500; ++i) {
        const float x = 0.5F * std::sin(2.0F * kPi * 1000.0F * static_cast<float>(i) / 48000.0F);
        const float y = notchFilter.ProcessSample(x);
        if (i > 100) {
            inPeak = std::max(inPeak, std::fabs(x));
            outPeak = std::max(outPeak, std::fabs(y));
        }
    }
    CHECK(std::fabs(inPeak - outPeak) < 0.01F);

    // 2. Add a notch at 2500 Hz (15dB attenuation)
    notchFilter.AddNotch(2500.0F, 15.0F, 25.0F);
    CHECK(notchFilter.ActiveNotchCount() == 1);

    // 2500 Hz tone should be heavily attenuated
    float peak2500 = 0.0F;
    for (int i = 0; i < 1000; ++i) {
        const float x = 0.5F * std::sin(2.0F * kPi * 2500.0F * static_cast<float>(i) / 48000.0F);
        const float y = notchFilter.ProcessSample(x);
        if (i > 300) {
            peak2500 = std::max(peak2500, std::fabs(y));
        }
    }
    // 15dB cut => amplitude is < 0.25x of original 0.5 (~0.1)
    CHECK(peak2500 < 0.15F);

    // Non-notched tone (1000 Hz) should still pass through
    notchFilter.Reset();
    notchFilter.AddNotch(2500.0F, 15.0F, 25.0F);
    float peak1000 = 0.0F;
    for (int i = 0; i < 500; ++i) {
        const float x = 0.5F * std::sin(2.0F * kPi * 1000.0F * static_cast<float>(i) / 48000.0F);
        const float y = notchFilter.ProcessSample(x);
        if (i > 100) {
            peak1000 = std::max(peak1000, std::fabs(y));
        }
    }
    CHECK(std::fabs(peak1000 - 0.5F) < 0.03F);

    // 3. Test auto-detection on a continuous howling feedback tone
    notchFilter.Reset();
    notchFilter.SetAutoDetectionEnabled(true);
    CHECK(notchFilter.ActiveNotchCount() == 0);
    for (int i = 0; i < 3000; ++i) {
        const float howling = 0.6F * std::sin(2.0F * kPi * 3000.0F * static_cast<float>(i) / 48000.0F);
        (void)notchFilter.ProcessSample(howling);
    }
    CHECK(notchFilter.ActiveNotchCount() >= 1);

    return 0;
}
