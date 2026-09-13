#include "karaoke/offline_mastering.h"
#include <cassert>
#include <iostream>
#include <vector>

using namespace karaoke;

void TestOfflineMastering() {
    MasteringConfig config;
    config.vocalGain = 1.0F;
    config.musicGain = 0.8F;
    config.reverbMix = 0.2F;
    config.pitchShiftSemitones = 0.0F;
    config.autoTuneStrength = 0.5F;

    std::vector<int16_t> dryVocal(480, 5000);
    std::vector<int16_t> musicStereo(960, 6000);

    std::vector<int16_t> outputStereo = OfflineMastering::Master(dryVocal, musicStereo, 480, config, 48000);
    assert(outputStereo.size() == 960);

    // Verify non-zero output
    bool nonZero = false;
    for (int16_t sample : outputStereo) {
        if (sample != 0) nonZero = true;
    }
    assert(nonZero);

    std::cout << "TestOfflineMastering passed!\n";
}

int main() {
    TestOfflineMastering();
    return 0;
}
