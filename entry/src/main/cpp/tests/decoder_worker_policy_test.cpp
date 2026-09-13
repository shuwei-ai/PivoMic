#include "karaoke/decoder_worker_policy.h"
#include <algorithm>
#include <array>
#include <cassert>
#include <vector>

class BoundedSink final : public karaoke::AccompanimentSink {
public:
  std::size_t Capacity() const noexcept override { return 4; }
  std::size_t Writable() const noexcept override { return allowance_; }
  std::size_t WriteStereo(const int16_t *samples,
                          std::size_t count) noexcept override {
    const auto written = std::min(count, allowance_ & ~std::size_t{1});
    received_.insert(received_.end(), samples, samples + written);
    allowance_ -= written;
    return written;
  }
  karaoke::ResetResult
  RequestResetAndWait(std::chrono::milliseconds,
                      const std::function<bool()> &) override {
    return karaoke::ResetResult::Completed;
  }
  void Allow(std::size_t count) { allowance_ = count; }
  const std::vector<int16_t> &Received() const { return received_; }

private:
  std::size_t allowance_{2};
  std::vector<int16_t> received_;
};

int main() {
  BoundedSink sink;
  karaoke::PendingStereoPcm pending;
  const std::array<int16_t, 8> samples{1, 2, 3, 4, 5, 6, 7, 8};
  pending.Assign(samples.data(), samples.size());
  assert(pending.DrainOnce(sink) == 2);
  assert(pending.PendingSamples() == 6); // pause: state is retained untouched
  sink.Allow(16);
  assert(pending.DrainOnce(sink, true) == 0);
  assert(pending.PendingSamples() == 6);
  sink.Allow(0);
  assert(pending.DrainOnce(sink) == 0);
  sink.Allow(16); // resume
  assert(pending.DrainOnce(sink) == 6);
  assert(!pending.HasPending());
  assert(sink.Received() ==
         std::vector<int16_t>(samples.begin(), samples.end()));

  karaoke::DecoderControlMailbox controls;
  controls.Seek(1000);
  const auto firstGeneration = controls.Generation();
  controls.Pause();
  assert(controls.ResetDisposition(firstGeneration) ==
         karaoke::ResetResult::Superseded);
  controls.Seek(2000);
  controls.Seek(3000);
  auto latest = controls.TakeLatestSeek();
  assert(latest && *latest == 3000);
  assert(!controls.TakeLatestSeek());
}
