#include "karaoke/realtime_mixer.h"

#include <cmath>
#include <cstdint>
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
    karaoke::RealtimeMixer mixer(48000, 480);
    mixer.SetAecEnabled(false);
    mixer.SetAntiHowlingEnabled(false);
    mixer.SetParametricEqEnabled(false);
    mixer.SetDeEsserEnabled(false);
    mixer.SetVocalDynamicsEnabled(false);
    mixer.SetPitchCorrection(false, 0.0F, 0, 0);
    mixer.SetGains(0.5F, 1.0F, 0.0F);
    mixer.SetAudioRoute(karaoke::AudioRouteMode::Wired);

    // 1. Basic accompaniment gain mixing.
    const int16_t music[] = {10000, -10000, 10000, -10000};
    const int16_t vocal[] = {0, 0};
    int16_t output[4] = {};
    mixer.Process(music, vocal, output, 2);
    CHECK(output[0] == 5000 && output[1] == -5000);
    CHECK(output[2] == 5000 && output[3] == -5000);

    // 2. Route changes apply on the next block without resetting the processing pipeline.
    mixer.Reset();
    mixer.SetGains(0.0F, 1.0F, 0.0F);
    const int16_t speakerVocal[] = {2000, 2000};
    mixer.SetAudioRoute(karaoke::AudioRouteMode::Wired);
    int16_t wiredVocalOutput[4] = {};
    mixer.Process(nullptr, speakerVocal, wiredVocalOutput, 2);
    CHECK(wiredVocalOutput[0] != 0 && wiredVocalOutput[1] != 0);
    CHECK(wiredVocalOutput[2] != 0 && wiredVocalOutput[3] != 0);

    mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
    int16_t speakerOutput[4] = {};
    mixer.Process(nullptr, speakerVocal, speakerOutput, 2);
    CHECK(speakerOutput[0] != 0 && speakerOutput[1] != 0);
    CHECK(speakerOutput[2] != 0 && speakerOutput[3] != 0);
    CHECK(std::abs(speakerOutput[0]) < std::abs(wiredVocalOutput[0]));

    mixer.SetAudioRoute(karaoke::AudioRouteMode::Bluetooth);
    int16_t bluetoothOutput[4] = {};
    mixer.Process(nullptr, speakerVocal, bluetoothOutput, 2);
    // In Bluetooth mode, live vocal monitoring is muted to prevent Bluetooth latency clash
    CHECK(bluetoothOutput[0] == 0 && bluetoothOutput[1] == 0);
    CHECK(bluetoothOutput[2] == 0 && bluetoothOutput[3] == 0);

    mixer.SetGains(1.0F, 1.0F, 0.0F);
    const int16_t musicFrame[] = {3000, 3000, 3000, 3000};
    int16_t bluetoothMusicOutput[4] = {};
    mixer.Process(musicFrame, speakerVocal, bluetoothMusicOutput, 2);
    // Accompaniment passes through with pristine fidelity
    CHECK(bluetoothMusicOutput[0] != 0 && bluetoothMusicOutput[1] != 0);

    mixer.SetGains(0.0F, 1.0F, 0.0F);

    mixer.SetAudioRoute(karaoke::AudioRouteMode::Wired);
    int16_t restoredOutput[4] = {};
    mixer.Process(nullptr, speakerVocal, restoredOutput, 2);
    CHECK(restoredOutput[0] != 0 && restoredOutput[1] != 0);
    CHECK(restoredOutput[2] != 0 && restoredOutput[3] != 0);

    // Speaker route keeps live processed vocal output and dual-track recording active.
    mixer.Reset();
    mixer.SetAudioRoute(karaoke::AudioRouteMode::Speaker);
    mixer.StartRecording();
    int16_t recordingOutput[4] = {};
    mixer.Process(music, speakerVocal, recordingOutput, 2);
    mixer.StopRecording();
    CHECK(mixer.RecordedFrames() == 2);
    CHECK(mixer.Recorder().VocalTrack()[0] != 0 && mixer.Recorder().VocalTrack()[1] != 0);
    CHECK(mixer.Recorder().MusicTrack()[0] == music[0] && mixer.Recorder().MusicTrack()[1] == music[1]);
    CHECK(mixer.Recorder().MusicTrack()[2] == music[2] && mixer.Recorder().MusicTrack()[3] == music[3]);

    // 5. Silence handling
    mixer.Reset();
    mixer.SetAudioRoute(karaoke::AudioRouteMode::Wired);
    const int16_t silenceMusic[8] = {};
    const int16_t silenceVocal[4] = {};
    int16_t silenceOutput[8] = {1, 1, 1, 1, 1, 1, 1, 1};
    mixer.SetGains(1.0F, 1.0F, 1.0F);
    mixer.Process(silenceMusic, silenceVocal, silenceOutput, 4);
    for (int16_t sample : silenceOutput) {
        CHECK(sample == 0);
    }

    // 6. Loud audio & soft limiting (no overflow or wrap-around)
    mixer.Reset();
    const int16_t loudMusic[] = {32767, 32767, -32768, -32768};
    const int16_t loudVocal[] = {32767, -32768};
    int16_t loudOutput[4] = {};
    mixer.Process(loudMusic, loudVocal, loudOutput, 2);
    CHECK(loudOutput[0] > 0 && loudOutput[1] > 0);
    CHECK(loudOutput[2] < 0 && loudOutput[3] < 0);

    // 7. Vocal dynamics / Noise gate test
    mixer.Reset();
    mixer.SetVocalDynamicsEnabled(true);
    mixer.SetGains(0.0F, 1.0F, 0.0F);
    constexpr int16_t quiet = 40; // Below -55 dBFS
    int16_t quietVocal[480];
    int16_t quietMusic[960] = {};
    int16_t quietOutput[960] = {};
    for (int16_t &sample : quietVocal) {
        sample = quiet;
    }
    for (int block = 0; block < 20; ++block) {
        mixer.Process(quietMusic, quietVocal, quietOutput, 480);
    }
    for (int index = 800; index < 960; ++index) {
        CHECK(quietOutput[index] == 0);
    }

    // 8. Spatial Reverb & presets
    mixer.Reset();
    mixer.SetVocalDynamicsEnabled(false);
    mixer.SetSpatialReverbEnabled(true);
    mixer.SetReverbPreset(karaoke::ReverbPreset::Concert);
    mixer.SetGains(0.0F, 0.0F, 1.0F);
    int16_t impulseVocal[480] = {};
    int16_t dryMusic[960] = {};
    int16_t wetOutput[960] = {};
    impulseVocal[0] = 12000;
    mixer.Process(dryMusic, impulseVocal, wetOutput, 480);
    mixer.Process(dryMusic, quietMusic, wetOutput, 480);
    mixer.Process(dryMusic, quietMusic, wetOutput, 480);
    bool hasTail = false;
    for (int16_t sample : wetOutput) {
        hasTail = hasTail || sample != 0;
    }
    CHECK(hasTail);

    // 7. Reset
    mixer.Reset();
    int16_t resetOutput[8] = {1, 1, 1, 1, 1, 1, 1, 1};
    mixer.Process(silenceMusic, silenceVocal, resetOutput, 4);
    for (int16_t sample : resetOutput) {
        CHECK(sample == 0);
    }

    // 8. Gain clamping & Peak measurement
    mixer.Reset();
    mixer.SetGains(-1.0F, 2.0F, 4.0F);
    CHECK(mixer.AccompanimentGain() == 0.0F);
    CHECK(mixer.VocalGain() == 2.0F);
    CHECK(mixer.ReverbGain() == 2.0F);
    const int16_t peakVocal[] = {16384};
    int16_t peakMusic[] = {0, 0};
    int16_t peakOutput[] = {0, 0};
    mixer.Process(peakMusic, peakVocal, peakOutput, 1);
    CHECK(mixer.Peak() >= 0.49F && mixer.Peak() <= 0.51F);
    CHECK(mixer.Peak() >= 0.0F && mixer.Peak() <= 1.0F);

    // 9. Boundary safety
    mixer.Process(nullptr, nullptr, nullptr, 0);
    int16_t oversizedMusic[962] = {};
    int16_t oversizedVocal[481] = {};
    int16_t oversizedOutput[962];
    for (int16_t &sample : oversizedOutput) {
        sample = 123;
    }
    mixer.Process(oversizedMusic, oversizedVocal, oversizedOutput, 481);
    CHECK(oversizedOutput[959] == 0);
    CHECK(oversizedOutput[960] == 123 && oversizedOutput[961] == 123);

    return 0;
}
