#ifndef PIVOMIC_KARAOKE_DECODED_PCM_PAYLOAD_H
#define PIVOMIC_KARAOKE_DECODED_PCM_PAYLOAD_H
#include <cstdint>
#include <cstring>
#include <vector>
namespace karaoke {
enum class DecodedPayloadKind { Pcm, Empty, EndOfStream, Error };
struct DecodedPcmPayload {
  DecodedPayloadKind kind{DecodedPayloadKind::Error};
  std::vector<int16_t> samples;
  std::size_t Frames(uint32_t channels) const noexcept {
    return channels == 0 ? 0 : samples.size() / channels;
  }
};
inline DecodedPcmPayload DecodePcmPayload(const uint8_t *buffer,
                                          int32_t capacity, int32_t offset,
                                          int32_t size, uint32_t channels,
                                          bool eos) {
  if (capacity < 0 || offset < 0 || size < 0 || channels == 0)
    return {};
  const uint64_t end = static_cast<uint64_t>(static_cast<uint32_t>(offset)) +
                       static_cast<uint32_t>(size);
  if (end > static_cast<uint32_t>(capacity))
    return {};
  if (size == 0)
    return {eos ? DecodedPayloadKind::EndOfStream : DecodedPayloadKind::Empty,
            {}};
  const std::size_t frameBytes = sizeof(int16_t) * channels;
  if (!buffer || static_cast<std::size_t>(size) % frameBytes != 0)
    return {};
  DecodedPcmPayload result{DecodedPayloadKind::Pcm, {}};
  result.samples.resize(static_cast<std::size_t>(size) / sizeof(int16_t));
  std::memcpy(result.samples.data(), buffer + offset,
              static_cast<std::size_t>(size));
  return result;
}
} // namespace karaoke
#endif
