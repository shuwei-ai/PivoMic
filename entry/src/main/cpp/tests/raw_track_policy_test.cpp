#include "karaoke/raw_track_policy.h"
#include <cassert>
#include <cstdint>

using karaoke::DecodePath;
using karaoke::PlanAudioTrack;

int main() {
  const auto raw = PlanAudioTrack("audio/raw", 8000, 1, 1, 16000, 48044);
  assert(raw.path == DecodePath::RawPcm);
  assert(raw.sampleRate == 8000);
  assert(raw.channels == 1);
  assert(raw.bufferCapacity == 16000);

  const auto rawFallback =
      PlanAudioTrack("audio/raw", 48000, 2, 1, 0, 288044);
  assert(rawFallback.path == DecodePath::RawPcm);
  assert(rawFallback.bufferCapacity >= 288000);

  assert(PlanAudioTrack("audio/raw", 48000, 2, 2, 4096, 10000).path ==
         DecodePath::Unsupported);
  assert(PlanAudioTrack("audio/raw", 0, 2, 1, 4096, 10000).path ==
         DecodePath::Unsupported);
  assert(PlanAudioTrack("audio/raw", 48000, 3, 1, 4096, 10000).path ==
         DecodePath::Unsupported);

  assert(PlanAudioTrack("audio/mpeg", 44100, 2, 0, 4096, 10000).path ==
         DecodePath::Codec);
  assert(PlanAudioTrack("audio/mp4a-latm", 48000, 2, 0, 4096, 10000)
             .path == DecodePath::Codec);
  assert(PlanAudioTrack(nullptr, 48000, 2, 1, 4096, 10000).path ==
         DecodePath::Unsupported);
  assert(PlanAudioTrack("audio/mpeg", 0, 2, 0, 4096, 10000).path ==
         DecodePath::Unsupported);
  return 0;
}
