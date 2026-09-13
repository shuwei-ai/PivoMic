#include "karaoke/accompaniment_sink.h"
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <thread>

int main() {
  karaoke::RingAccompanimentSink sink(16);
  const std::array<int16_t, 4> stereo{1, 2, 3, 4};
  assert(sink.WriteStereo(stereo.data(), stereo.size()) == stereo.size());
  sink.SetRendererActive(false);
  assert(sink.RequestResetAndWait(std::chrono::milliseconds(20), [] {
    return false;
  }) == karaoke::ResetResult::Completed);
  assert(sink.Writable() == sink.Capacity());

  assert(sink.WriteStereo(stereo.data(), stereo.size()) == stereo.size());
  sink.SetRendererActive(true);
  std::atomic<bool> acked{false};
  std::thread callback([&] {
    while (!sink.ConsumeResetOnRenderer())
      std::this_thread::yield();
    acked = true;
  });
  assert(sink.RequestResetAndWait(std::chrono::milliseconds(100), [] {
    return false;
  }) == karaoke::ResetResult::Completed);
  callback.join();
  assert(acked && sink.Writable() == sink.Capacity());

  assert(sink.WriteStereo(stereo.data(), stereo.size()) == stereo.size());
  sink.SetRendererActive(true);
  const auto before = std::chrono::steady_clock::now();
  assert(sink.RequestResetAndWait(std::chrono::milliseconds(500), [] {
    return true;
  }) == karaoke::ResetResult::Superseded);
  assert(std::chrono::steady_clock::now() - before <
         std::chrono::milliseconds(100));
}
