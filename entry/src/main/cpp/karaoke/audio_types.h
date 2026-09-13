#ifndef PIVOMIC_KARAOKE_AUDIO_TYPES_H
#define PIVOMIC_KARAOKE_AUDIO_TYPES_H

#include <cstdint>

namespace karaoke {

struct AudioFormat {
    std::uint32_t sampleRate {48000};
    std::uint32_t channelCount {2};
};

enum class EngineError {
    None,
    InvalidTransition,
    AudioUnavailable,
    DecoderFailure,
    InternalFailure,
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_AUDIO_TYPES_H
