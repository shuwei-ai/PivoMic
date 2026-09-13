#include "karaoke/dual_track_recorder.h"
#include <cassert>
#include <iostream>
#include <vector>

using namespace karaoke;

void TestDualTrackRecording() {
    DualTrackRecorder recorder;
    assert(!recorder.IsRecording());
    assert(recorder.RecordedFrames() == 0);

    // Push while not recording -> should be ignored
    std::vector<int16_t> vocal(480, 500);
    std::vector<int16_t> music(960, 200);
    recorder.PushFrame(vocal.data(), music.data(), 480);
    assert(recorder.RecordedFrames() == 0);

    // Start recording
    recorder.StartRecording();
    assert(recorder.IsRecording());

    recorder.PushFrame(vocal.data(), music.data(), 480);
    assert(recorder.RecordedFrames() == 480);
    assert(recorder.RecordedDurationMs() == 10); // 480 samples @ 48kHz = 10ms

    // Check recorded vectors
    assert(recorder.VocalTrack().size() >= 480);
    assert(recorder.VocalTrack()[0] == 500);
    assert(recorder.MusicTrack().size() >= 960);
    assert(recorder.MusicTrack()[0] == 200);

    // Stop recording
    recorder.StopRecording();
    assert(!recorder.IsRecording());

    std::cout << "TestDualTrackRecording passed!\n";
}

int main() {
    TestDualTrackRecording();
    return 0;
}
