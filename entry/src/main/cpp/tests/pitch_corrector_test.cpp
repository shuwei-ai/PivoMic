#include "karaoke/pitch_corrector.h"
#include <cmath>
#include <cassert>
#include <iostream>
#include <vector>

using namespace karaoke;

void TestPitchQuantization() {
    PitchCorrector corrector(48000);
    corrector.SetEnabled(true);
    corrector.SetStrength(1.0F);
    corrector.SetScale(PitchScaleType::Chromatic, 0);

    // Test note quantization: 440Hz is A4 (midi 69)
    float targetA4 = corrector.QuantizePitchToScale(440.0F);
    assert(std::fabs(targetA4 - 440.0F) < 1.0F);

    // 445Hz should snap back toward 440Hz in chromatic
    float targetSnap = corrector.QuantizePitchToScale(445.0F);
    assert(std::fabs(targetSnap - 440.0F) < 1.0F);

    // Major scale quantization test
    corrector.SetScale(PitchScaleType::Major, 0); // C Major
    // C4 is 261.63Hz (midi 60)
    float targetC4 = corrector.QuantizePitchToScale(261.63F);
    assert(std::fabs(targetC4 - 261.63F) < 1.0F);

    std::cout << "TestPitchQuantization passed!\n";
}

void TestPitchCorrectionProcessing() {
    PitchCorrector corrector(48000);
    corrector.SetEnabled(true);
    corrector.SetStrength(0.8F);

    std::vector<float> sine(480);
    for (size_t i = 0; i < sine.size(); ++i) {
        sine[i] = 0.5F * std::sin(2.0F * 3.14159265F * 440.0F * static_cast<float>(i) / 48000.0F);
    }

    std::vector<float> output(480);
    corrector.Process(sine.data(), output.data(), 480);

    // Ensure output is finite and not silent
    bool nonZero = false;
    for (float sample : output) {
        assert(std::isfinite(sample));
        if (std::fabs(sample) > 0.01F) nonZero = true;
    }
    assert(nonZero);

    std::cout << "TestPitchCorrectionProcessing passed!\n";
}

int main() {
    TestPitchQuantization();
    TestPitchCorrectionProcessing();
    return 0;
}
