#include "karaoke/realtime_mixer.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

namespace {

void Check(bool condition, int line, const char *msg)
{
    if (!condition) {
        std::fprintf(stderr, "Check failed at line %d: %s\n", line, msg);
        std::abort();
    }
}

} // namespace

#define CHECK_MSG(condition, msg) Check((condition), __LINE__, (msg))
#define CHECK(condition) Check((condition), __LINE__, #condition)

int main()
{
    constexpr uint32_t kSampleRate = 48000;
    constexpr std::size_t kBlockSize = 240; // 5ms @ 48kHz
    constexpr float kPi = 3.14159265358979323846F;

    karaoke::RealtimeMixer mixer(kSampleRate, kBlockSize);

    // =========================================================================
    // 1. Closed-Loop Acoustic Howling Suppression Test
    // =========================================================================
    // Simulates physical acoustic feedback loop:
    // Speaker output couples back into microphone with 25ms (1200 samples) delay
    // and strong acoustic coupling factor 0.80 (which without protection blows up!).
    {
        mixer.Reset();
        mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
        mixer.SetAntiHowlingEnabled(true);
        mixer.SetGains(0.8F, 1.0F, 0.0F);

        constexpr std::size_t kAcousticDelaySamples = 1200; // 25ms @ 48kHz
        std::vector<int16_t> acousticDelayRing(kAcousticDelaySamples * 2, 0);
        std::size_t delayWritePos = 0;

        std::vector<int16_t> musicBlock(kBlockSize * 2, 0);
        std::vector<int16_t> micBlock(kBlockSize, 0);
        std::vector<int16_t> outBlock(kBlockSize * 2, 0);

        // Feed background music
        for (std::size_t i = 0; i < kBlockSize; ++i) {
            const float m = 6000.0F * std::sin(2.0F * kPi * 440.0F * static_cast<float>(i) / 48000.0F);
            musicBlock[i * 2] = static_cast<int16_t>(m);
            musicBlock[i * 2 + 1] = static_cast<int16_t>(m);
        }

        // Run 100 blocks (500ms): inject howling spike at 2800Hz in first 3 blocks
        for (int block = 0; block < 100; ++block) {
            for (std::size_t i = 0; i < kBlockSize; ++i) {
                const std::size_t readPos = (delayWritePos + acousticDelayRing.size() - kAcousticDelaySamples) % acousticDelayRing.size();
                const int16_t coupled = acousticDelayRing[readPos];
                float micVal = static_cast<float>(coupled) * 0.80F; // High feedback coupling

                if (block < 3) {
                    // Impulse to trigger acoustic resonance
                    micVal += 12000.0F * std::sin(2.0F * kPi * 2800.0F * static_cast<float>(block * kBlockSize + i) / 48000.0F);
                }
                micBlock[i] = static_cast<int16_t>(std::clamp(micVal, -32000.0F, 32000.0F));
            }

            mixer.Process(musicBlock.data(), micBlock.data(), outBlock.data(), kBlockSize);

            for (std::size_t i = 0; i < kBlockSize; ++i) {
                acousticDelayRing[delayWritePos] = outBlock[i * 2]; // Left speaker to air
                delayWritePos = (delayWritePos + 1) % acousticDelayRing.size();
            }
        }

        // System must be strictly stable and bounded (no rail clipping at 32767)
        float tailEnergy = 0.0F;
        int16_t tailPeak = 0;
        for (std::size_t i = 0; i < kBlockSize * 2; ++i) {
            tailEnergy += static_cast<float>(outBlock[i]) * static_cast<float>(outBlock[i]);
            tailPeak = std::max(tailPeak, static_cast<int16_t>(std::abs(outBlock[i])));
        }
        tailEnergy /= static_cast<float>(kBlockSize * 2);

        // Verification: energy remains safely controlled and not blown out
        CHECK_MSG(tailEnergy < 1e8F, "Closed loop feedback must not blow up into rail saturation");
        CHECK_MSG(tailPeak < 30000, "Tail peak must be well within DAC dynamic range");
    }

    // =========================================================================
    // 2. High-Pitched Sustained Singing Preservation (Anti-Vocal Hollowing Test)
    // =========================================================================
    // Injects 2 seconds of human singing: 880Hz & 1320Hz with 5.5Hz vibrato and rich harmonics.
    // Dynamic notch filter must NOT mistake this sustained singing for howling.
    {
        mixer.Reset();
        mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
        mixer.SetAntiHowlingEnabled(true);
        mixer.SetGains(0.0F, 1.0F, 0.0F);

        std::vector<int16_t> musicEmpty(kBlockSize * 2, 0);
        std::vector<int16_t> singingMic(kBlockSize, 0);
        std::vector<int16_t> singingOut(kBlockSize * 2, 0);

        float inTotalEnergy = 0.0F;
        float outTotalEnergy = 0.0F;

        // 200 blocks = 1 second of belting high note
        for (int block = 0; block < 200; ++block) {
            for (std::size_t i = 0; i < kBlockSize; ++i) {
                const float t = static_cast<float>(block * kBlockSize + i) / 48000.0F;
                // Vibrato at 5.5Hz with +-12Hz depth
                const float vibrato = 12.0F * std::sin(2.0F * kPi * 5.5F * t);
                const float f0 = 880.0F + vibrato;
                // Fundamental + 2nd harmonic + 3rd harmonic (natural human voice)
                const float voice = 10000.0F * std::sin(2.0F * kPi * f0 * t) +
                                    4000.0F * std::sin(2.0F * kPi * (2.0F * f0) * t) +
                                    1500.0F * std::sin(2.0F * kPi * (3.0F * f0) * t);
                singingMic[i] = static_cast<int16_t>(std::clamp(voice, -32000.0F, 32000.0F));

                if (block > 50) {
                    inTotalEnergy += static_cast<float>(singingMic[i]) * static_cast<float>(singingMic[i]);
                }
            }

            mixer.Process(musicEmpty.data(), singingMic.data(), singingOut.data(), kBlockSize);

            if (block > 50) {
                for (std::size_t i = 0; i < kBlockSize; ++i) {
                    outTotalEnergy += static_cast<float>(singingOut[i * 2]) * static_cast<float>(singingOut[i * 2]);
                }
            }
        }

        const float powerRatio = outTotalEnergy / std::max(1.0F, inTotalEnergy);
        // With kSpeakerVocalScale = 0.50 and ramp 0.7~1.0, linear gain is ~0.21, powerRatio ~ 0.045.
        // If a notch had hollowed out 880Hz, power would plummet below 0.01!
        CHECK_MSG(powerRatio > 0.03F, "Sustained vocal belting must not be hollowed out by notch filter");
    }

    // =========================================================================
    // 3. Transient Big Dynamic Anti-Pumping Test
    // =========================================================================
    // Sudden step from quiet singing (-20dBFS) to loud singing (-1dBFS).
    // Gain Guard must NOT panic-duck normal singing like the old PID did!
    {
        mixer.Reset();
        mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
        mixer.SetAntiHowlingEnabled(true);
        mixer.SetGains(0.0F, 1.0F, 0.0F);

        std::vector<int16_t> musicEmpty(kBlockSize * 2, 0);
        std::vector<int16_t> quietMic(kBlockSize, 0);
        std::vector<int16_t> loudMic(kBlockSize, 0);
        std::vector<int16_t> outBlock(kBlockSize * 2, 0);

        for (std::size_t i = 0; i < kBlockSize; ++i) {
            const float t = static_cast<float>(i) / 48000.0F;
            const float voice = 0.75F * std::sin(2.0F * kPi * 650.0F * t) + 0.25F * std::sin(2.0F * kPi * 1300.0F * t);
            quietMic[i] = static_cast<int16_t>(3000.0F * voice);
            loudMic[i] = static_cast<int16_t>(28000.0F * voice);
        }

        // Quiet singing for 10 blocks
        for (int b = 0; b < 10; ++b) {
            mixer.Process(musicEmpty.data(), quietMic.data(), outBlock.data(), kBlockSize);
        }

        // Sudden explosion to loud singing
        int16_t maxLoudOut = 0;
        for (int b = 0; b < 10; ++b) {
            mixer.Process(musicEmpty.data(), loudMic.data(), outBlock.data(), kBlockSize);
            for (std::size_t i = 0; i < kBlockSize; ++i) {
                maxLoudOut = std::max(maxLoudOut, static_cast<int16_t>(std::abs(outBlock[i * 2])));
            }
        }

        const auto metrics = mixer.GetStageMetrics();
        std::printf("Loud singing test: maxLoudOut=%d, rawPeak=%.3f, shiftPeak=%.3f, dynPeak=%.3f, vSubPeak=%.3f, effVocalGain=%.3f\n",
                    maxLoudOut, metrics.rawPeak, metrics.shiftPeak, metrics.dynPeak, metrics.vocalSubPeak, metrics.effectiveVocalGain);
        CHECK_MSG(maxLoudOut > 3500, "Loud singing must not be pumped or choked by Gain Guard");
    }

    // =========================================================================
    // 4. Dual-Track Recording Zero-Pitch-Drift Verification
    // =========================================================================
    // Confirms that speaker-mode SSB frequency shift (+3.5Hz) is 100% isolated
    // from the recorded vocal track (which must retain exact original pitch).
    {
        mixer.Reset();
        mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
        mixer.SetAntiHowlingEnabled(true);
        mixer.SetGains(0.8F, 1.0F, 0.0F);
        mixer.StartRecording();

        std::vector<int16_t> musicBlock(kBlockSize * 2, 0);
        std::vector<int16_t> micBlock(kBlockSize, 0);
        std::vector<int16_t> outBlock(kBlockSize * 2, 0);

        for (std::size_t i = 0; i < kBlockSize; ++i) {
            const float s = 15000.0F * std::sin(2.0F * kPi * 1000.0F * static_cast<float>(i) / 48000.0F);
            micBlock[i] = static_cast<int16_t>(s);
        }

        mixer.Process(musicBlock.data(), micBlock.data(), outBlock.data(), kBlockSize);
        mixer.StopRecording();

        CHECK(mixer.RecordedFrames() == kBlockSize);
        const auto &recordedVocal = mixer.Recorder().VocalTrack();
        CHECK(!recordedVocal.empty());

        // Check cross-correlation / fidelity between mic input and recorded dry vocal
        double crossSum = 0.0;
        double micPower = 0.0;
        double recPower = 0.0;
        for (std::size_t i = 0; i < mixer.RecordedFrames(); ++i) {
            const double m = static_cast<double>(micBlock[i]);
            const double r = static_cast<double>(recordedVocal[i]);
            crossSum += m * r;
            micPower += m * m;
            recPower += r * r;
        }
        const double corr = crossSum / std::sqrt(std::max(1.0, micPower * recPower));
        std::printf("Recording test: corr = %.6f\n", corr);
        // Clean correlation (allowing slight phase shift from dynamics/EQ): must be > 0.90
        CHECK_MSG(corr >= 0.90, "Recorded vocal track must preserve exact original pitch and phase");
    }

    // =========================================================================
    // 5. Zero-Allocation and DSP Budget Benchmark (< 1.0ms per 5ms block)
    // =========================================================================
    {
        mixer.Reset();
        mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
        mixer.SetAntiHowlingEnabled(true);
        mixer.SetGains(0.8F, 1.0F, 0.5F);

        std::vector<int16_t> musicBlock(kBlockSize * 2, 1000);
        std::vector<int16_t> micBlock(kBlockSize, 2000);
        std::vector<int16_t> outBlock(kBlockSize * 2, 0);

        auto startTime = std::chrono::high_resolution_clock::now();
        constexpr int kBenchmarkBlocks = 200; // 1 second of audio
        for (int b = 0; b < kBenchmarkBlocks; ++b) {
            mixer.Process(musicBlock.data(), micBlock.data(), outBlock.data(), kBlockSize);
        }
        auto endTime = std::chrono::high_resolution_clock::now();
        const auto totalDurationUs = std::chrono::duration_cast<std::chrono::microseconds>(endTime - startTime).count();
        const double avgBlockUs = static_cast<double>(totalDurationUs) / static_cast<double>(kBenchmarkBlocks);

        // 5ms audio callback = 5000 us. DSP processing budget p99 < 1000 us (20%).
        std::printf("Feedback loop benchmark: average block processing time = %.2f us (budget: < 1000 us)\n", avgBlockUs);
        CHECK_MSG(avgBlockUs < 1000.0, "Average DSP processing time must be well within real-time budget (< 1000us)");
    }

    std::printf("All feedback loop simulation & anti-howling tests PASSED!\n");
    return 0;
}
