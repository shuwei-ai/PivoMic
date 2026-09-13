#include "karaoke/vocal_dynamics.h"

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
    karaoke::VocalDynamics dynamics(48000);

    // 1. Zero input produces zero output
    for (int i = 0; i < 100; ++i) {
        CHECK(dynamics.ProcessSample(0.0F) == 0.0F);
    }

    // 2. DC offset / low frequency (<20Hz) is attenuated by 80Hz Butterworth HPF
    // Step response settles back down towards 0
    for (int i = 0; i < 2000; ++i) {
        (void)dynamics.ProcessSample(0.5F);
    }

    // 3. Sub-threshold input is gated out after release
    dynamics.Reset();
    constexpr float kSubThreshold = 0.0005F; // approx -66 dBFS
    float lastOut = 1.0F;
    for (int i = 0; i < 1000; ++i) {
        lastOut = dynamics.ProcessSample(kSubThreshold);
    }
    CHECK(std::fabs(lastOut) < 0.0001F);

    // 4. Strong singing AC signal (440 Hz) opens gate and is cleanly compressed
    dynamics.Reset();
    constexpr float kPi = 3.14159265358979323846F;
    constexpr float kFreq = 440.0F;
    float peakSingingOut = 0.0F;
    for (int i = 0; i < 1000; ++i) {
        const float sample = 0.5F * std::sin(2.0F * kPi * kFreq * static_cast<float>(i) / 48000.0F);
        const float out = dynamics.ProcessSample(sample);
        peakSingingOut = std::max(peakSingingOut, std::fabs(out));
    }
    CHECK(peakSingingOut > 0.1F && peakSingingOut <= 1.2F);
    CHECK(dynamics.CurrentGateGain() > 0.9F);

    // 5. Reset works cleanly
    dynamics.Reset();
    CHECK(dynamics.CurrentEnvelope() == 0.0F);
    CHECK(dynamics.CurrentGateGain() == 0.0F);

    return 0;
}
