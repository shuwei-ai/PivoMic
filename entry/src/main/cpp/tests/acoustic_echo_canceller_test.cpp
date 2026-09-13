#include "karaoke/acoustic_echo_canceller.h"

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
    karaoke::AcousticEchoCanceller aec(48000);
    constexpr std::size_t kTestFrames = 48000; // 1 second
    constexpr std::size_t kAcousticDelay = 48; // 1 ms delay

    std::vector<float> ref(kTestFrames);
    std::vector<float> mic(kTestFrames, 0.0F);
    std::vector<float> out(kTestFrames, 0.0F);

    // 1. Generate rich accompaniment playback reference
    uint32_t state = 987654321;
    for (std::size_t i = 0; i < kTestFrames; ++i) {
        state ^= (state << 13);
        state ^= (state >> 17);
        state ^= (state << 5);
        const float noise = static_cast<float>(static_cast<int32_t>(state)) / 2147483648.0F;
        ref[i] = noise * 0.4F;

        // Simulated room impulse response (direct path at 48 samples + reflection at 70 samples)
        if (i >= kAcousticDelay) {
            mic[i] += ref[i - kAcousticDelay] * 0.6F;
        }
        if (i >= kAcousticDelay + 22) {
            mic[i] += ref[i - (kAcousticDelay + 22)] * 0.25F;
        }
    }

    aec.SetAlignmentDelay(kAcousticDelay);

    // Process first 0.5s: Single talk (pure accompaniment echo)
    for (std::size_t i = 0; i < kTestFrames / 2; ++i) {
        out[i] = aec.ProcessSample(mic[i], ref[i]);
    }

    // Check convergence: Error at end of 0.5s should be significantly smaller than mic echo
    float micTailEnergy = 0.0F;
    float errTailEnergy = 0.0F;
    for (std::size_t i = kTestFrames / 2 - 2000; i < kTestFrames / 2; ++i) {
        micTailEnergy += mic[i] * mic[i];
        errTailEnergy += out[i] * out[i];
    }

    const float erleDb = 10.0F * std::log10(micTailEnergy / std::max(errTailEnergy, 1e-8F));
    std::printf("Single-talk converged ERLE: %.2f dB (micEnergy: %f, errEnergy: %f)\n",
                erleDb, micTailEnergy, errTailEnergy);
    CHECK(erleDb > 10.0F); // Attenuation > 10dB

    // 2. Double-talk test: Add strong singing voice (440 Hz tone) on top of accompaniment
    constexpr float kPi = 3.14159265358979323846F;
    float singingPeak = 0.0F;
    float outSingingPeak = 0.0F;
    for (std::size_t i = kTestFrames / 2; i < kTestFrames; ++i) {
        const float vocal = 0.5F * std::sin(2.0F * kPi * 440.0F * static_cast<float>(i) / 48000.0F);
        mic[i] += vocal; // Mic receives both echo and singing
        out[i] = aec.ProcessSample(mic[i], ref[i]);

        if (i > kTestFrames - 2000) {
            singingPeak = std::max(singingPeak, std::fabs(vocal));
            outSingingPeak = std::max(outSingingPeak, std::fabs(out[i]));
        }
    }

    std::printf("Double-talk vocal preservation: inPeak=%.3f, outPeak=%.3f, isDoubleTalk=%d\n",
                singingPeak, outSingingPeak, aec.IsDoubleTalk());
    // Vocal should be preserved cleanly (no swallowing)
    CHECK(outSingingPeak > 0.4F && outSingingPeak < 0.85F);

    return 0;
}
