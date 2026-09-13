#include "karaoke/accompaniment_pitch_shifter.h"
#include <cmath>
#include <cassert>
#include <iostream>
#include <vector>

using namespace karaoke;

void TestPitchShifterBypass() {
    AccompanimentPitchShifter shifter(48000);
    shifter.SetSemitones(0.0F);
    assert(std::fabs(shifter.Semitones()) < 0.001F);

    std::vector<float> input(480 * 2, 0.4F);
    std::vector<float> output(480 * 2, 0.0F);

    shifter.ProcessStereo(input.data(), output.data(), 480);

    for (size_t i = 0; i < output.size(); ++i) {
        assert(std::fabs(output[i] - 0.4F) < 1e-4F);
    }

    std::cout << "TestPitchShifterBypass passed!\n";
}

void TestPitchShiftRangeAndProcessing() {
    AccompanimentPitchShifter shifter(48000);
    shifter.SetSemitones(2.0F); // Transpose +2 semitones
    assert(std::fabs(shifter.Semitones() - 2.0F) < 0.001F);

    // Clamping test
    shifter.SetSemitones(10.0F);
    assert(std::fabs(shifter.Semitones() - 6.0F) < 0.001F);
    shifter.SetSemitones(-10.0F);
    assert(std::fabs(shifter.Semitones() - (-6.0F)) < 0.001F);

    shifter.SetSemitones(1.0F);
    std::vector<float> sine(960);
    for (size_t i = 0; i < 480; ++i) {
        float val = 0.5F * std::sin(2.0F * 3.14159265F * 220.0F * static_cast<float>(i) / 48000.0F);
        sine[i * 2] = val;
        sine[i * 2 + 1] = val;
    }

    std::vector<float> output(960, 0.0F);
    shifter.ProcessStereo(sine.data(), output.data(), 480);

    for (float sample : output) {
        assert(std::isfinite(sample));
        assert(sample <= 1.0F && sample >= -1.0F);
    }

    std::cout << "TestPitchShiftRangeAndProcessing passed!\n";
}

int main() {
    TestPitchShifterBypass();
    TestPitchShiftRangeAndProcessing();
    return 0;
}
