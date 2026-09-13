#ifndef PIVOMIC_KARAOKE_AUDIO_CAPABILITY_PROBE_H
#define PIVOMIC_KARAOKE_AUDIO_CAPABILITY_PROBE_H

namespace karaoke {

struct AudioCapabilities {
    bool aecSupported {false};
};

class AudioCapabilityProbe final {
public:
    [[nodiscard]] static AudioCapabilities Probe() noexcept;
};

} // namespace karaoke

#endif
