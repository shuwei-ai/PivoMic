#include "karaoke/linear_resampler.h"

#include <array>
#include <cstdlib>
#include <iostream>
#include <vector>

#define CHECK(x)                                                               \
  do {                                                                         \
    if (!(x)) {                                                                \
      std::cerr << "CHECK failed: " #x << " line " << __LINE__ << '\n';        \
      std::abort();                                                            \
    }                                                                          \
  } while (false)

using karaoke::LinearResampler;

static void Identity() {
  LinearResampler r;
  const std::array<int16_t, 6> in{1, -2, 300, -400, 32767, -32768};
  std::array<int16_t, 8> out{};
  auto result = r.Process(in.data(), 3, 48000, 2, out.data(), 4);
  CHECK(result.ok && result.consumedFrames == 3 && result.producedFrames == 3);
  CHECK(std::equal(in.begin(), in.end(), out.begin()));
}

static void MonoAcrossChunks() {
  LinearResampler r;
  std::array<int16_t, 16> out{};
  const std::array<int16_t, 2> a{0, 1000};
  auto first = r.Process(a.data(), 2, 24000, 1, out.data(), 8);
  CHECK(first.ok && first.consumedFrames == 2 && first.producedFrames == 3);
  const std::array<int16_t, 2> b{2000, 3000};
  auto second = r.Process(b.data(), 2, 24000, 1, out.data() + 6, 5);
  CHECK(second.ok && second.consumedFrames == 2 && second.producedFrames == 4);
  const std::array<int16_t, 14> expected{0,    0,    500,  500,  1000,
                                         1000, 1500, 1500, 2000, 2000,
                                         2500, 2500, 3000, 3000};
  CHECK(std::equal(expected.begin(), expected.end(), out.begin()));
}

static void ChunkingAndCapacityDoNotChange44100Output() {
  std::vector<int16_t> input(442);
  for (std::size_t i = 0; i < input.size(); ++i)
    input[i] = static_cast<int16_t>(i * 37 - 7000);
  std::vector<int16_t> whole(1200), split(1200);
  LinearResampler a, b;
  auto one = a.Process(input.data(), input.size(), 44100, 1, whole.data(),
                       whole.size() / 2);
  std::size_t consumed = 0, produced = 0;
  while (consumed < input.size()) {
    auto part = b.Process(input.data() + consumed,
                          std::min<std::size_t>(17, input.size() - consumed),
                          44100, 1, split.data() + produced * 2, 7);
    CHECK(part.ok && (part.consumedFrames != 0 || part.producedFrames != 0));
    consumed += part.consumedFrames;
    produced += part.producedFrames;
  }
  while (produced < one.producedFrames) {
    auto part = b.Process(nullptr, 0, 44100, 1, split.data() + produced * 2, 7);
    if (part.producedFrames == 0)
      break;
    produced += part.producedFrames;
  }
  CHECK(consumed == input.size() && produced == one.producedFrames);
  CHECK(std::equal(whole.begin(),
                   whole.begin() + static_cast<std::ptrdiff_t>(produced * 2),
                   split.begin()));
}

static void StereoDownsampleAndReset() {
  LinearResampler r;
  const std::array<int16_t, 8> in{10, 20, 30, 40, 50, 60, 70, 80};
  std::array<int16_t, 8> out{};
  auto result = r.Process(in.data(), 4, 96000, 2, out.data(), 4);
  CHECK(result.ok && result.consumedFrames == 4 && result.producedFrames == 2);
  CHECK(out[0] == 10 && out[1] == 20 && out[2] == 50 && out[3] == 60);
  r.Reset();
  const std::array<int16_t, 1> mono{900};
  result = r.Process(mono.data(), 1, 24000, 1, out.data(), 4);
  CHECK(result.ok && out[0] == 900 && out[1] == 900);
}

static void InvalidAndBounded() {
  LinearResampler r;
  std::array<int16_t, 6> guarded{111, 222, 0, 0, 333, 444};
  const std::array<int16_t, 4> in{1, 2, 3, 4};
  CHECK(!r.Process(nullptr, 2, 48000, 2, guarded.data() + 2, 1).ok);
  CHECK(!r.Process(in.data(), 2, 0, 2, guarded.data() + 2, 1).ok);
  CHECK(!r.Process(in.data(), 2, 48000, 0, guarded.data() + 2, 1).ok);
  CHECK(!r.Process(in.data(), 2, 48000, 3, guarded.data() + 2, 1).ok);
  auto result = r.Process(in.data(), 2, 48000, 2, guarded.data() + 2, 1);
  CHECK(result.ok && result.producedFrames == 1 && result.consumedFrames == 1);
  CHECK(guarded[0] == 111 && guarded[1] == 222 && guarded[4] == 333 &&
        guarded[5] == 444);
}

int main() {
  Identity();
  MonoAcrossChunks();
  ChunkingAndCapacityDoNotChange44100Output();
  StereoDownsampleAndReset();
  InvalidAndBounded();
}
