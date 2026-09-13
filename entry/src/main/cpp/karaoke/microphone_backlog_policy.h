#ifndef PIVOMIC_MICROPHONE_BACKLOG_POLICY_H
#define PIVOMIC_MICROPHONE_BACKLOG_POLICY_H

#include "spsc_audio_ring.h"

namespace karaoke {

// 48kHz mono capture. Call once per FULL renderer callback, before its block loop.
// Allow 40ms scheduling jitter beyond the requested callback; recover to 10ms
// headroom only when that limit is exceeded. This bounds persistent FIFO delay
// without cutting normally batched callbacks. It does not measure hardware latency.
template<typename T>
std::size_t TrimMicrophoneBacklog(SpscAudioRing<T>& ring, std::size_t callbackFrames) noexcept
{
    const std::size_t queued = ring.Readable();
    if (queued <= callbackFrames || queued - callbackFrames <= 1920) return 0;
    return ring.Discard(queued - callbackFrames - 480);
}

} // namespace karaoke
#endif
