#include "karaoke/audio_route_manager.h"
#include <cassert>
#include <iostream>

using namespace karaoke;

void TestRouteManagerBasics() {
    AudioRouteManager manager;
    assert(manager.CurrentMode() == AudioRouteMode::Speaker);
    assert(manager.CurrentPolicy().isEarReturnMuted == false);
    assert(manager.CurrentPolicy().isAntiHowlingActive == true);
    assert(manager.CurrentPolicy().isAecRequired == true);

    // Switch to Bluetooth (Ear-return muted to avoid car/TWS 200ms latency conflict)
    manager.SetMode(AudioRouteMode::Bluetooth);
    assert(manager.CurrentMode() == AudioRouteMode::Bluetooth);
    assert(manager.CurrentPolicy().isEarReturnMuted == true);
    assert(manager.CurrentPolicy().allowLowLatencyEarReturn == false);
    assert(manager.CurrentPolicy().isAecRequired == false);

    // Switch to SpeakerWithEarReturn
    manager.SetMode(AudioRouteMode::SpeakerWithEarReturn);
    assert(manager.CurrentMode() == AudioRouteMode::SpeakerWithEarReturn);
    assert(manager.CurrentPolicy().isEarReturnMuted == false);
    assert(manager.CurrentPolicy().isAntiHowlingActive == true);
    assert(manager.CurrentPolicy().isAecRequired == true);

    // Switch to Wired
    manager.SetMode(AudioRouteMode::Wired);
    assert(manager.CurrentMode() == AudioRouteMode::Wired);
    assert(manager.CurrentPolicy().isEarReturnMuted == false);
    assert(manager.CurrentPolicy().allowLowLatencyEarReturn == true);

    std::cout << "AudioRouteManagerBasics passed!\n";
}

int main() {
    TestRouteManagerBasics();
    return 0;
}
