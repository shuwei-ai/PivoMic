#include "audio_capability_probe.h"

#ifdef __OHOS__
#include <ohaudio/native_audio_stream_manager.h>
#endif

namespace karaoke {

AudioCapabilities AudioCapabilityProbe::Probe() noexcept
{
    AudioCapabilities capabilities;
#ifdef __OHOS__
    OH_AudioStreamManager *manager = nullptr;
    if (OH_AudioManager_GetAudioStreamManager(&manager) != AUDIOCOMMON_RESULT_SUCCESS || manager == nullptr) {
        return capabilities;
    }
    bool supported = false;
    if (OH_AudioStreamManager_IsAcousticEchoCancelerSupported(
            manager, AUDIOSTREAM_SOURCE_TYPE_VOICE_COMMUNICATION, &supported) == AUDIOCOMMON_RESULT_SUCCESS) {
        capabilities.aecSupported = supported;
    }
#endif
    return capabilities;
}

} // namespace karaoke
