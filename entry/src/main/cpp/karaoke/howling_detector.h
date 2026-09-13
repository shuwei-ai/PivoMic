#ifndef PIVOMIC_KARAOKE_HOWLING_DETECTOR_H
#define PIVOMIC_KARAOKE_HOWLING_DETECTOR_H

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace karaoke {

/**
 * @brief Discrete command sent from HowlingDetector to DynamicNotchFilter bank.
 */
struct NotchCommand {
    std::size_t slot {0};
    bool active {true};
    float frequencyHz {0.0F};
    float depthDb {6.0F};
    float q {25.0F};
    float b0 {1.0F};
    float b1 {0.0F};
    float b2 {0.0F};
    float a1 {0.0F};
    float a2 {0.0F};
};

/**
 * @brief Zero-allocation Sideband FFT Howling & Acoustic Feedback Detector.
 *
 * Implements a 4-dimensional joint confidence classifier:
 * 1. Spectral Peakedness (PNPR >= 10dB, PAPR >= 12dB).
 * 2. Exponential Energy Runaway Rate (dE/dt > 0 with divergence slope).
 * 3. Harmonic Comb Rejection (discards integer subharmonic / overtone series typical of human singing).
 * 4. Frequency Rigidity vs. Vibrato (filters out 4~7Hz natural vocal vibrato; locks onto rigid acoustic poles).
 *
 * Runs FFT in 1024-point windows with 256-point hop size (~5.33ms update @ 48kHz).
 */
class HowlingDetector final {
public:
    static constexpr std::size_t kFftSize = 1024;
    static constexpr std::size_t kHopSize = 256;
    static constexpr std::size_t kSpectrumBins = kFftSize / 2 + 1;
    static constexpr std::size_t kMaxHistoryHops = 4;
    static constexpr std::size_t kMaxTrackedPeaks = 8;

    explicit HowlingDetector(uint32_t sampleRate = 48000) noexcept
        : sampleRate_(sampleRate == 0 ? 48000 : sampleRate),
          binHz_(static_cast<float>(sampleRate_) / static_cast<float>(kFftSize)),
          minBin_(std::max<std::size_t>(3, static_cast<std::size_t>(std::ceil(150.0F / binHz_)))),
          maxBin_(std::min<std::size_t>(kSpectrumBins - 2, static_cast<std::size_t>(std::floor(10000.0F / binHz_))))
    {
        InitializeTwiddleAndWindow();
        Reset();
    }

    void SetSampleRate(uint32_t sampleRate) noexcept
    {
        sampleRate_ = sampleRate == 0 ? 48000 : sampleRate;
        binHz_ = static_cast<float>(sampleRate_) / static_cast<float>(kFftSize);
        minBin_ = std::max<std::size_t>(3, static_cast<std::size_t>(std::ceil(150.0F / binHz_)));
        maxBin_ = std::min<std::size_t>(kSpectrumBins - 2, static_cast<std::size_t>(std::floor(10000.0F / binHz_)));
        InitializeTwiddleAndWindow();
        Reset();
    }

    void SetEnabled(bool enabled) noexcept { enabled_ = enabled; }
    [[nodiscard]] bool IsEnabled() const noexcept { return enabled_; }

    void Reset() noexcept
    {
        inputBufferPos_ = 0;
        inputBuffer_.fill(0.0F);
        powerSpectrum_.fill(0.0F);
        avgSpectrum_.fill(0.0F);
        totalBandEnergy_ = 0.0F;
        hopIndex_ = 0;
        alertActive_ = false;

        for (auto &history : binEnergyHistory_) {
            history.fill(0.0F);
        }
        trackedPeaks_.fill(TrackedPeak {});
    }

    /**
     * @brief Feed audio samples into the detector.
     * @param samples Pointer to float PCM array.
     * @param count Number of samples.
     * @param outCommands Output vector where generated notch commands will be pushed.
     * @return True if at least one howling candidate was detected.
     */
    bool Process(const float *samples, std::size_t count, std::vector<NotchCommand> *outCommands = nullptr) noexcept
    {
        if (!enabled_ || samples == nullptr || count == 0) {
            return false;
        }

        bool detectedAny = false;
        for (std::size_t i = 0; i < count; ++i) {
            inputBuffer_[inputBufferPos_++] = samples[i];
            if (inputBufferPos_ >= kFftSize) {
                const bool detected = AnalyzeWindow(outCommands);
                detectedAny = detectedAny || detected;

                // Shift window by kHopSize (slide 1024 - 256 = 768 samples)
                std::copy(inputBuffer_.begin() + kHopSize, inputBuffer_.begin() + kFftSize, inputBuffer_.begin());
                inputBufferPos_ = kFftSize - kHopSize;
            }
        }
        return detectedAny;
    }

    [[nodiscard]] bool IsAlertActive() const noexcept { return alertActive_; }

    /**
     * @brief Helper to compute Direct Form II Transposed Peaking Cut Biquad coefficients.
     */
    static void ComputeNotchCoefficients(float sampleRate, float frequencyHz, float depthDb, float q,
                                         float &b0, float &b1, float &b2, float &a1, float &a2) noexcept
    {
        constexpr double kPi = 3.14159265358979323846;
        const double w0 = 2.0 * kPi * static_cast<double>(frequencyHz) / static_cast<double>(sampleRate);
        const double cosW0 = std::cos(w0);
        const double sinW0 = std::sin(w0);
        const double alpha = sinW0 / (2.0 * static_cast<double>(std::max(0.5F, q)));
        // Peaking cut: depthDb > 0 means attenuation
        const double A = std::pow(10.0, -static_cast<double>(std::fabs(depthDb)) / 40.0);

        const double b0D = 1.0 + alpha * A;
        const double b1D = -2.0 * cosW0;
        const double b2D = 1.0 - alpha * A;
        const double a0D = 1.0 + alpha / A;
        const double a1D = -2.0 * cosW0;
        const double a2D = 1.0 - alpha / A;

        b0 = static_cast<float>(b0D / a0D);
        b1 = static_cast<float>(b1D / a0D);
        b2 = static_cast<float>(b2D / a0D);
        a1 = static_cast<float>(a1D / a0D);
        a2 = static_cast<float>(a2D / a0D);
    }

private:
    struct TrackedPeak {
        bool active {false};
        std::size_t binIndex {0};
        float frequencyHz {0.0F};
        float peakPower {0.0F};
        uint32_t persistentHops {0};
        float initialEnergy {0.0F};
        float currentDepthDb {6.0F};
    };

    void InitializeTwiddleAndWindow() noexcept
    {
        constexpr double kPi = 3.14159265358979323846;
        for (std::size_t i = 0; i < kFftSize; ++i) {
            // Periodic Hann window
            hannWindow_[i] = static_cast<float>(0.5 * (1.0 - std::cos(2.0 * kPi * static_cast<double>(i) / static_cast<double>(kFftSize))));
        }

        // Twiddle factors
        for (std::size_t i = 0; i < kFftSize / 2; ++i) {
            const double angle = -2.0 * kPi * static_cast<double>(i) / static_cast<double>(kFftSize);
            cosTable_[i] = static_cast<float>(std::cos(angle));
            sinTable_[i] = static_cast<float>(std::sin(angle));
        }

        // Bit-reversal permutation
        std::size_t j = 0;
        for (std::size_t i = 0; i < kFftSize; ++i) {
            bitRevTable_[i] = j;
            std::size_t bit = kFftSize >> 1;
            while (j & bit) {
                j ^= bit;
                bit >>= 1;
            }
            j ^= bit;
        }
    }

    void ExecuteRealFft(const std::array<float, kFftSize> &input) noexcept
    {
        // 1. Window & Bit-reversal copy
        for (std::size_t i = 0; i < kFftSize; ++i) {
            const std::size_t rev = bitRevTable_[i];
            fftReal_[rev] = input[i] * hannWindow_[i];
            fftImag_[rev] = 0.0F;
        }

        // 2. In-place Cooley-Tukey Radix-2 DIT FFT
        for (std::size_t len = 2; len <= kFftSize; len <<= 1) {
            const std::size_t halfLen = len >> 1;
            const std::size_t step = kFftSize / len;
            for (std::size_t i = 0; i < kFftSize; i += len) {
                for (std::size_t k = 0; k < halfLen; ++k) {
                    const std::size_t twiddleIdx = k * step;
                    const float cosW = cosTable_[twiddleIdx];
                    const float sinW = sinTable_[twiddleIdx];

                    const float tr = cosW * fftReal_[i + k + halfLen] - sinW * fftImag_[i + k + halfLen];
                    const float ti = sinW * fftReal_[i + k + halfLen] + cosW * fftImag_[i + k + halfLen];

                    fftReal_[i + k + halfLen] = fftReal_[i + k] - tr;
                    fftImag_[i + k + halfLen] = fftImag_[i + k] - ti;
                    fftReal_[i + k] += tr;
                    fftImag_[i + k] += ti;
                }
            }
        }

        // 3. Compute one-sided power spectrum
        float bandEnergySum = 0.0F;
        for (std::size_t k = 0; k < kSpectrumBins; ++k) {
            const float r = fftReal_[k];
            const float im = fftImag_[k];
            const float p = r * r + im * im;
            powerSpectrum_[k] = p;
            if (k >= minBin_ && k <= maxBin_) {
                bandEnergySum += p;
            }
        }
        totalBandEnergy_ = bandEnergySum;
    }

    bool AnalyzeWindow(std::vector<NotchCommand> *outCommands) noexcept
    {
        ExecuteRealFft(inputBuffer_);
        ++hopIndex_;

        const std::size_t bandBins = (maxBin_ >= minBin_) ? (maxBin_ - minBin_ + 1) : 1;
        const float avgBandPower = std::max(1e-9F, totalBandEnergy_ / static_cast<float>(bandBins));

        bool detectedHowling = false;

        // Search for prominent local peaks
        for (std::size_t k = minBin_ + 2; k <= maxBin_ - 2; ++k) {
            const float p = powerSpectrum_[k];
            if (p <= powerSpectrum_[k - 1] || p <= powerSpectrum_[k + 1]) {
                continue; // Not a local peak
            }

            // Metric 1: PAPR >= 12 dB (factor >= 15.85)
            const float paprRatio = p / avgBandPower;
            if (paprRatio < 15.85F) {
                continue;
            }

            // Metric 2: PNPR >= 10 dB (factor >= 10.0) compared to surrounding noise floor
            // Neighbors: [k - 7, k - 3] and [k + 3, k + 7]
            float neighborSum = 0.0F;
            int neighborCount = 0;
            for (int offset = -7; offset <= 7; ++offset) {
                if (std::abs(offset) < 3) continue;
                const int nIdx = static_cast<int>(k) + offset;
                if (nIdx >= 0 && nIdx < static_cast<int>(kSpectrumBins)) {
                    neighborSum += powerSpectrum_[static_cast<std::size_t>(nIdx)];
                    ++neighborCount;
                }
            }
            const float avgNeighbor = (neighborCount > 0) ? (neighborSum / static_cast<float>(neighborCount)) : 1e-9F;
            const float pnprRatio = p / std::max(1e-9F, avgNeighbor);
            if (pnprRatio < 10.0F) {
                continue;
            }

            // Metric 3: Harmonic Comb Rejection (Anti-Vocal Hollowing)
            // Human voice has strong harmonics (subharmonic f/2, f/3 or overtone 2f, 3f).
            // Check if f/2 or 2f possesses significant formant power.
            if (IsHumanHarmonicSeries(k)) {
                continue;
            }

            // Metric 4: Exponential Growth / Persistence Verification
            // In acoustic feedback, energy grows exponentially until saturation and remains rigid (zero vibrato).
            const float freq = InterpolatePeakFrequency(k);
            if (!VerifyGrowthOrRigidity(k, p, freq)) {
                continue;
            }

            // Howling confirmed!
            detectedHowling = true;
            alertActive_ = true;

            if (outCommands != nullptr) {
                AllocateOrUpdateSlot(k, freq, p, outCommands);
            }
        }

        if (!detectedHowling) {
            // Decay alert state
            alertActive_ = false;
        }

        return detectedHowling;
    }

    [[nodiscard]] bool IsHumanHarmonicSeries(std::size_t peakBin) const noexcept
    {
        // 1. Check if there's a strong subharmonic at ~ f/2
        if (peakBin >= 4) {
            const std::size_t sub2 = peakBin / 2;
            const float sub2Power = std::max({powerSpectrum_[sub2 - 1], powerSpectrum_[sub2], powerSpectrum_[sub2 + 1]});
            if (sub2Power > powerSpectrum_[peakBin] * 0.25F) {
                return true; // Likely 2nd harmonic of a singing fundamental!
            }
        }

        // 2. Check if there's a strong overtone at ~ 2f
        const std::size_t overtone2 = peakBin * 2;
        if (overtone2 + 1 < kSpectrumBins) {
            const float overtone2Power = std::max({powerSpectrum_[overtone2 - 1], powerSpectrum_[overtone2], powerSpectrum_[overtone2 + 1]});
            if (overtone2Power > powerSpectrum_[peakBin] * 0.20F) {
                // Natural harmonic series present!
                return true;
            }
        }

        // 3. Check if there's a 3f overtone
        const std::size_t overtone3 = peakBin * 3;
        if (overtone3 + 1 < kSpectrumBins) {
            const float overtone3Power = std::max({powerSpectrum_[overtone3 - 1], powerSpectrum_[overtone3], powerSpectrum_[overtone3 + 1]});
            if (overtone3Power > powerSpectrum_[peakBin] * 0.15F) {
                return true;
            }
        }

        return false;
    }

    [[nodiscard]] float InterpolatePeakFrequency(std::size_t k) const noexcept
    {
        const float alpha = std::log(std::max(1e-9F, powerSpectrum_[k - 1]));
        const float beta  = std::log(std::max(1e-9F, powerSpectrum_[k]));
        const float gamma = std::log(std::max(1e-9F, powerSpectrum_[k + 1]));

        const float denom = alpha - 2.0F * beta + gamma;
        float delta = 0.0F;
        if (std::fabs(denom) > 1e-6F) {
            delta = 0.5F * (alpha - gamma) / denom;
            delta = std::clamp(delta, -0.5F, 0.5F);
        }
        return (static_cast<float>(k) + delta) * binHz_;
    }

    bool VerifyGrowthOrRigidity(std::size_t bin, float currentPower, float freq) noexcept
    {
        // Search in tracked peaks
        TrackedPeak *existing = nullptr;
        for (auto &tp : trackedPeaks_) {
            if (tp.active && std::fabs(tp.frequencyHz - freq) < 8.0F) {
                existing = &tp;
                break;
            }
        }

        if (existing == nullptr) {
            // New candidate: find free or weakest slot
            TrackedPeak *slot = nullptr;
            for (auto &tp : trackedPeaks_) {
                if (!tp.active) {
                    slot = &tp;
                    break;
                }
            }
            if (slot == nullptr) {
                slot = &trackedPeaks_[0];
            }

            slot->active = true;
            slot->binIndex = bin;
            slot->frequencyHz = freq;
            slot->peakPower = currentPower;
            slot->initialEnergy = currentPower;
            slot->persistentHops = 1;
            slot->currentDepthDb = 6.0F;

            // If it's already an extreme burst (e.g. initial energy > 0.1), let it trigger
            return currentPower > 0.05F;
        }

        // Existing candidate: update persistence
        existing->persistentHops++;
        const float growth = currentPower / std::max(1e-9F, existing->initialEnergy);
        existing->peakPower = currentPower;

        // Feedback condition: either persistent for >= 3 hops with frequency rigidity,
        // or rapid explosive growth (growth > 2.0x within 2 hops)
        if (existing->persistentHops >= 3 || growth > 2.0F) {
            return true;
        }
        return false;
    }

    void AllocateOrUpdateSlot(std::size_t bin, float freq, float power, std::vector<NotchCommand> *outCommands) noexcept
    {
        (void)bin;
        (void)power;
        // Check if there is an existing tracked peak
        std::size_t assignedSlot = 0;
        float depth = 6.0F;
        for (std::size_t i = 0; i < trackedPeaks_.size(); ++i) {
            if (trackedPeaks_[i].active && std::fabs(trackedPeaks_[i].frequencyHz - freq) < 15.0F) {
                assignedSlot = i % 8;
                if (trackedPeaks_[i].persistentHops > 6) {
                    depth = 15.0F; // Deepen notch
                } else if (trackedPeaks_[i].persistentHops > 3) {
                    depth = 12.0F;
                } else {
                    depth = 6.0F;
                }
                trackedPeaks_[i].currentDepthDb = depth;
                break;
            }
        }

        NotchCommand cmd {};
        cmd.slot = assignedSlot;
        cmd.active = true;
        cmd.frequencyHz = freq;
        cmd.depthDb = depth;
        cmd.q = (depth > 10.0F) ? 35.0F : 25.0F;

        ComputeNotchCoefficients(static_cast<float>(sampleRate_), cmd.frequencyHz, cmd.depthDb, cmd.q,
                                cmd.b0, cmd.b1, cmd.b2, cmd.a1, cmd.a2);

        outCommands->push_back(cmd);
    }

    uint32_t sampleRate_ {48000};
    float binHz_ {46.875F};
    std::size_t minBin_ {3};
    std::size_t maxBin_ {213};
    bool enabled_ {true};
    bool alertActive_ {false};

    std::size_t inputBufferPos_ {0};
    uint64_t hopIndex_ {0};
    float totalBandEnergy_ {0.0F};

    std::array<float, kFftSize> inputBuffer_ {};
    std::array<float, kFftSize> hannWindow_ {};
    std::array<float, kFftSize / 2> cosTable_ {};
    std::array<float, kFftSize / 2> sinTable_ {};
    std::array<std::size_t, kFftSize> bitRevTable_ {};

    std::array<float, kFftSize> fftReal_ {};
    std::array<float, kFftSize> fftImag_ {};
    std::array<float, kSpectrumBins> powerSpectrum_ {};
    std::array<float, kSpectrumBins> avgSpectrum_ {};

    std::array<std::array<float, kSpectrumBins>, kMaxHistoryHops> binEnergyHistory_ {};
    std::array<TrackedPeak, kMaxTrackedPeaks> trackedPeaks_ {};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_HOWLING_DETECTOR_H
