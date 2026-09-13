#include "karaoke/anti_howling_shifter.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

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
    karaoke::AntiHowlingShifter shifter(48000, 4.0F);
    CHECK(shifter.IsEnabled());
    CHECK(shifter.FrequencyShift() == 4.0F);

    // 1. Zero input produces zero output
    for (int i = 0; i < 100; ++i) {
        const float out = shifter.ProcessSample(0.0F);
        CHECK(std::fabs(out) < 1e-6F);
    }

    // 2. Continuous sine wave processing (1000 Hz) produces bounded, shifted output
    constexpr float kPi = 3.14159265358979323846F;
    constexpr float kFreq = 1000.0F;
    std::vector<float> input(4800);
    std::vector<float> output(4800);
    for (std::size_t n = 0; n < input.size(); ++n) {
        input[n] = std::sin(2.0F * kPi * kFreq * static_cast<float>(n) / 48000.0F);
    }

    output = input;
    shifter.Process(output.data(), output.size());

    // Check that output is not silent and bounded within [-1.5, 1.5]
    float maxAbs = 0.0F;
    for (float s : output) {
        maxAbs = std::max(maxAbs, std::fabs(s));
        CHECK(std::isfinite(s));
        CHECK(std::fabs(s) <= 1.5F);
    }
    CHECK(maxAbs > 0.5F);

    // Steady state check (after first 500 samples filter warmup)
    float steadyMax = 0.0F;
    for (std::size_t i = 500; i < output.size(); ++i) {
        steadyMax = std::max(steadyMax, std::fabs(output[i]));
    }
    CHECK(steadyMax >= 0.8F && steadyMax <= 1.2F);

    // 3. Bypass / Disabled mode passes input unchanged
    shifter.SetEnabled(false);
    CHECK(!shifter.IsEnabled());
    float testVal = 0.75F;
    CHECK(shifter.ProcessSample(testVal) == testVal);

    shifter.SetEnabled(true);
    shifter.Reset();
    CHECK(shifter.ProcessSample(0.0F) == 0.0F);

    // 4. Nullptr safety
    shifter.Process(nullptr, 0);

    return 0;
}
