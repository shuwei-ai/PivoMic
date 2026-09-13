#ifndef PIVOMIC_KARAOKE_OFFLINE_MASTERING_H
#define PIVOMIC_KARAOKE_OFFLINE_MASTERING_H

#include "accompaniment_pitch_shifter.h"
#include "de_esser.h"
#include "lookahead_limiter.h"
#include "parametric_eq.h"
#include "pitch_corrector.h"
#include "spatial_reverb.h"
#include "vocal_dynamics.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace karaoke {

struct MasteringConfig {
    float vocalGain {1.0F};
    float musicGain {1.0F};
    float reverbMix {0.25F};
    float pitchShiftSemitones {0.0F};
    float autoTuneStrength {0.0F};
    PitchScaleType autoTuneScale {PitchScaleType::Chromatic};
    uint32_t autoTuneRoot {0};
    uint32_t reverbPreset {0}; // 0=Ktv, 1=Studio, 2=Concert, 3=Folk
};

class OfflineMastering final {
public:
    static constexpr float kPcmScale = 32768.0F;

    /**
     * @brief Remaster recorded dual-tracks into a studio-quality stereo master track.
     */
    static std::vector<int16_t> Master(
        const std::vector<int16_t>& dryVocalMono,
        const std::vector<int16_t>& accompanimentStereo,
        std::size_t frames,
        const MasteringConfig& config,
        uint32_t sampleRate = 48000) noexcept
    {
        if (frames == 0 || (dryVocalMono.empty() && accompanimentStereo.empty())) {
            return {};
        }

        std::vector<int16_t> outputStereo(frames * 2, 0);

        // Instantiate mastering DSP chain
        AccompanimentPitchShifter pitchShifter(sampleRate);
        pitchShifter.SetSemitones(config.pitchShiftSemitones);

        PitchCorrector autoTune(sampleRate);
        if (config.autoTuneStrength > 0.01F) {
            autoTune.SetEnabled(true);
            autoTune.SetStrength(config.autoTuneStrength);
            autoTune.SetScale(config.autoTuneScale, config.autoTuneRoot);
        }

        VocalDynamics dynamics(sampleRate);
        DeEsser deEsser(sampleRate);
        ParametricEQ eq(sampleRate);
        SpatialReverb reverb(sampleRate);

        switch (config.reverbPreset) {
            case 1: reverb.SetRoomSize(0.45F); reverb.SetDamping(0.60F); break; // Studio
            case 2: reverb.SetRoomSize(0.90F); reverb.SetDamping(0.20F); break; // Concert
            case 3: reverb.SetRoomSize(0.60F); reverb.SetDamping(0.45F); break; // Folk
            default: reverb.SetRoomSize(0.75F); reverb.SetDamping(0.35F); break; // Ktv
        }

        LookaheadLimiter limiter(sampleRate, 1.5F);

        std::vector<float> musicBlock(512 * 2, 0.0F);
        constexpr std::size_t kBlockSize = 512;

        for (std::size_t offset = 0; offset < frames; offset += kBlockSize) {
            const std::size_t blockFrames = std::min(kBlockSize, frames - offset);

            // 1. Process Accompaniment Block
            for (std::size_t i = 0; i < blockFrames; ++i) {
                const std::size_t idx = offset + i;
                if (idx * 2 + 1 < accompanimentStereo.size()) {
                    musicBlock[i * 2] = accompanimentStereo[idx * 2] / kPcmScale;
                    musicBlock[i * 2 + 1] = accompanimentStereo[idx * 2 + 1] / kPcmScale;
                } else {
                    musicBlock[i * 2] = musicBlock[i * 2 + 1] = 0.0F;
                }
            }
            pitchShifter.ProcessStereo(musicBlock.data(), blockFrames);

            // 2. Process Vocal and Master Mix
            for (std::size_t i = 0; i < blockFrames; ++i) {
                const std::size_t idx = offset + i;
                float vocal = (idx < dryVocalMono.size()) ? (dryVocalMono[idx] / kPcmScale) : 0.0F;

                // AutoTune -> Dynamics -> DeEsser -> EQ -> Reverb
                vocal = autoTune.ProcessSample(vocal);
                vocal = dynamics.ProcessSample(vocal);
                vocal = deEsser.ProcessSample(vocal);
                vocal = eq.ProcessSample(vocal);

                float wetL = 0.0F;
                float wetR = 0.0F;
                reverb.ProcessSample(vocal, wetL, wetR);

                const float musicL = musicBlock[i * 2] * config.musicGain;
                const float musicR = musicBlock[i * 2 + 1] * config.musicGain;

                const float mixL = musicL + vocal * config.vocalGain + wetL * config.reverbMix;
                const float mixR = musicR + vocal * config.vocalGain + wetR * config.reverbMix;

                // Soft Limiter & Quantization
                const float limitedL = SoftLimit(mixL);
                const float limitedR = SoftLimit(mixR);

                outputStereo[idx * 2] = static_cast<int16_t>(std::clamp(limitedL * kPcmScale, -32768.0F, 32767.0F));
                outputStereo[idx * 2 + 1] = static_cast<int16_t>(std::clamp(limitedR * kPcmScale, -32768.0F, 32767.0F));
            }
        }

        return outputStereo;
    }

private:
    static float SoftLimit(float sample) noexcept
    {
        constexpr float kCeiling = 0.96605F; // -0.3 dBFS
        const float magnitude = std::fabs(sample);
        if (magnitude <= 0.8F) {
            return sample;
        }
        const float limited = 0.8F + 0.2F * (1.0F - std::exp(-(magnitude - 0.8F) * 5.0F));
        const float clamped = std::copysign(std::min(limited, 1.0F), sample);
        return std::max(-kCeiling, std::min(clamped, kCeiling));
    }
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_OFFLINE_MASTERING_H
