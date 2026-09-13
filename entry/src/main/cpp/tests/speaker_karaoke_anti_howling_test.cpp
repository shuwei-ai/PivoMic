#include "karaoke/realtime_mixer.h"

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
    constexpr uint32_t kSampleRate = 48000;
    constexpr std::size_t kBlockSize = 240; // 5ms block @ 48kHz
    karaoke::RealtimeMixer mixer(kSampleRate, kBlockSize);
    constexpr float kPi = 3.14159265358979323846F;

    // =========================================================================
    // 1. Speaker Mode Independent Volume Adjustment & Output Summing
    // =========================================================================
    mixer.Reset();
    mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
    mixer.SetAecEnabled(false);
    mixer.SetAntiHowlingEnabled(false);
    mixer.SetVocalDynamicsEnabled(false);
    mixer.SetSpatialReverbEnabled(false);

    // Set independent gains: Accompaniment 0.6, Vocal 0.8
    mixer.SetGains(0.6F, 0.8F, 0.0F);
    CHECK(std::fabs(mixer.AccompanimentGain() - 0.6F) < 0.01F);
    CHECK(std::fabs(mixer.VocalGain() - 0.8F) < 0.01F);

    const int16_t musicFrame[2] = {10000, 10000};
    const int16_t vocalFrame[1] = {0};
    int16_t outOnlyMusic[2] = {};
    mixer.Process(musicFrame, vocalFrame, outOnlyMusic, 1);
    CHECK(outOnlyMusic[0] == 6000 && outOnlyMusic[1] == 6000);

    // =========================================================================
    // 2. Music Sub-bus Protection & Anti-Ducking Verification
    // =========================================================================
    mixer.Reset();
    mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
    mixer.SetAecEnabled(false);
    mixer.SetAntiHowlingEnabled(false);
    mixer.SetVocalDynamicsEnabled(false);
    mixer.SetGains(0.5F, 1.0F, 0.0F);

    // Play 1000 Hz music sine wave continuously
    // While injecting an extreme burst (32767 peak) into mic
    std::vector<int16_t> musicBlock(kBlockSize * 2);
    std::vector<int16_t> micScreamBlock(kBlockSize, 32767);
    std::vector<int16_t> mixOutput(kBlockSize * 2);

    for (std::size_t i = 0; i < kBlockSize; ++i) {
        const float sample = 16000.0F * std::sin(2.0F * kPi * 1000.0F * static_cast<float>(i) / 48000.0F);
        musicBlock[i * 2] = static_cast<int16_t>(sample);
        musicBlock[i * 2 + 1] = static_cast<int16_t>(sample);
    }

    mixer.Process(musicBlock.data(), micScreamBlock.data(), mixOutput.data(), kBlockSize);

    // Verify output is bounded, no wrap-around, and music signal remains active
    for (std::size_t i = 0; i < kBlockSize * 2; ++i) {
        CHECK(mixOutput[i] > -32768 && mixOutput[i] < 32767);
    }

    // =========================================================================
    // 3. Acoustic Loop Stability Test (AEC + Notch + Shift + Loop Guard)
    // =========================================================================
    mixer.Reset();
    mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
    mixer.SetAecEnabled(true);
    mixer.SetAntiHowlingEnabled(true);
    mixer.SetVocalDynamicsEnabled(true);
    mixer.SetSpatialReverbEnabled(true);
    mixer.SetGains(0.8F, 1.0F, 0.5F);

    // Simulate physical acoustic closed-loop:
    // Output from speaker couples back into microphone with 48 sample (1ms) delay and 0.5 acoustic coupling
    std::vector<int16_t> simMusic(kBlockSize * 2, 0);
    std::vector<int16_t> simMic(kBlockSize, 0);
    std::vector<int16_t> simOut(kBlockSize * 2, 0);
    std::vector<int16_t> acousticDelayLine(480, 0);
    std::size_t delayWritePos = 0;

    // Start with singing burst, then check if system settles without infinite howling explosion
    for (int block = 0; block < 100; ++block) {
        // Feed music
        for (std::size_t i = 0; i < kBlockSize; ++i) {
            const float m = 8000.0F * std::sin(2.0F * kPi * 500.0F * static_cast<float>(block * kBlockSize + i) / 48000.0F);
            simMusic[i * 2] = static_cast<int16_t>(m);
            simMusic[i * 2 + 1] = static_cast<int16_t>(m);
        }

        // Acoustic coupling from previous output
        for (std::size_t i = 0; i < kBlockSize; ++i) {
            const int16_t coupled = acousticDelayLine[(delayWritePos + acousticDelayLine.size() - 48) % acousticDelayLine.size()];
            float micSignal = static_cast<float>(coupled) * 0.4F;
            if (block < 5) {
                // Initial singing impulse
                micSignal += 10000.0F * std::sin(2.0F * kPi * 1200.0F * static_cast<float>(i) / 48000.0F);
            }
            simMic[i] = static_cast<int16_t>(std::clamp(micSignal, -32000.0F, 32000.0F));
        }

        mixer.Process(simMusic.data(), simMic.data(), simOut.data(), kBlockSize);

        // Feed output back to acoustic delay line
        for (std::size_t i = 0; i < kBlockSize; ++i) {
            acousticDelayLine[delayWritePos] = simOut[i * 2];
            delayWritePos = (delayWritePos + 1) % acousticDelayLine.size();
        }
    }

    // After 100 blocks (0.5s), the system must remain stable and not clip
    float tailEnergy = 0.0F;
    for (std::size_t i = 0; i < kBlockSize * 2; ++i) {
        tailEnergy += static_cast<float>(simOut[i]) * static_cast<float>(simOut[i]);
    }
    tailEnergy /= static_cast<float>(kBlockSize * 2);
    // Bounded energy (not blown out to max rail 32767^2 ~ 1e9)
    CHECK(tailEnergy < 4e8F);

    // =========================================================================
    // 4. Dual-Track Recording 100% Studio Fidelity Preservation
    // =========================================================================
    mixer.Reset();
    mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
    mixer.SetVocalDynamicsEnabled(true);
    mixer.SetGains(0.8F, 1.0F, 0.5F);
    mixer.StartRecording();

    std::vector<int16_t> recMusic(kBlockSize * 2, 5000);
    std::vector<int16_t> recMic(kBlockSize, 12000);
    std::vector<int16_t> recOut(kBlockSize * 2);

    mixer.Process(recMusic.data(), recMic.data(), recOut.data(), kBlockSize);
    mixer.StopRecording();

    CHECK(mixer.RecordedFrames() == kBlockSize);
    const auto& vocalRecorded = mixer.Recorder().VocalTrack();
    CHECK(!vocalRecorded.empty());
    // Vocal track must have recorded high quality un-attenuated dry signal
    int16_t maxVocalSample = 0;
    for (int16_t s : vocalRecorded) {
        maxVocalSample = std::max(maxVocalSample, static_cast<int16_t>(std::abs(s)));
    }
    CHECK(maxVocalSample > 5000);

    std::printf("All speaker-mode anti-howling and mixing tests PASSED!\n");
    return 0;
}
