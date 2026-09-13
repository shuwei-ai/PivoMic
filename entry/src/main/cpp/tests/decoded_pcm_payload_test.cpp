#include "karaoke/decoded_pcm_payload.h"
#include <array>
#include <cassert>
#include <cstdint>
#include <limits>

int main() {
  using karaoke::DecodedPayloadKind;
  using karaoke::DecodePcmPayload;

  const std::array<std::uint8_t, 9> misaligned{0xff, 0x01, 0x00, 0xfe, 0xff,
                                               0x34, 0x12, 0xcc, 0xdd};
  auto payload =
      DecodePcmPayload(misaligned.data(), misaligned.size(), 1, 6, 1, false);
  assert(payload.kind == DecodedPayloadKind::Pcm);
  assert((payload.samples == std::vector<std::int16_t>{1, -2, 0x1234}));

  assert(DecodePcmPayload(misaligned.data(), misaligned.size(), 1, 5, 1, false)
             .kind == DecodedPayloadKind::Error);
  assert(DecodePcmPayload(misaligned.data(), misaligned.size(), 1, 6, 2, false)
             .kind == DecodedPayloadKind::Error);
  assert(DecodePcmPayload(misaligned.data(), misaligned.size(), 7, 4, 1, false)
             .kind == DecodedPayloadKind::Error);
  assert(DecodePcmPayload(misaligned.data(),
                          std::numeric_limits<std::int32_t>::max(),
                          std::numeric_limits<std::int32_t>::max() - 1,
                          std::numeric_limits<std::int32_t>::max(), 1, false)
             .kind == DecodedPayloadKind::Error);

  assert(DecodePcmPayload(nullptr, 0, 0, 0, 2, true).kind ==
         DecodedPayloadKind::EndOfStream);
  assert(DecodePcmPayload(nullptr, 0, 0, 0, 2, false).kind ==
         DecodedPayloadKind::Empty);
  assert(DecodePcmPayload(nullptr, 8, 0, 4, 2, false).kind ==
         DecodedPayloadKind::Error);
}
