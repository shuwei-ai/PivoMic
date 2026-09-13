#ifndef PIVOMIC_KARAOKE_RAW_TRACK_POLICY_H
#define PIVOMIC_KARAOKE_RAW_TRACK_POLICY_H

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <limits>

namespace karaoke {

enum class DecodePath { Unsupported, RawPcm, Codec };

struct AudioTrackPlan {
  DecodePath path{DecodePath::Unsupported};
  int32_t sampleRate{0};
  int32_t channels{0};
  int32_t bufferCapacity{0};
};

inline AudioTrackPlan PlanAudioTrack(const char *mime, int32_t sampleRate,
                                     int32_t channels, int32_t sampleFormat,
                                     int32_t maxInputSize,
                                     int64_t sourceSize) noexcept {
  if (!mime || sampleRate <= 0 || channels <= 0)
    return {};
  const bool raw = std::strcmp(mime, "audio/raw") == 0;
  if (!raw)
    return {DecodePath::Codec, sampleRate, channels, 0};
  if (sampleFormat != 1 || (channels != 1 && channels != 2))
    return {};
  constexpr int64_t kFallbackLimit = 4 * 1024 * 1024;
  int64_t capacity = maxInputSize > 0
                         ? maxInputSize
                         : std::min(std::max<int64_t>(sourceSize, 1),
                                    kFallbackLimit);
  capacity = std::min<int64_t>(capacity, std::numeric_limits<int32_t>::max());
  return {DecodePath::RawPcm, sampleRate, channels,
          static_cast<int32_t>(capacity)};
}

} // namespace karaoke
#endif
