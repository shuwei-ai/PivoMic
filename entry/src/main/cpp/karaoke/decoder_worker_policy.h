#ifndef PIVOMIC_KARAOKE_DECODER_WORKER_POLICY_H
#define PIVOMIC_KARAOKE_DECODER_WORKER_POLICY_H
#include "accompaniment_sink.h"
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <optional>
#include <vector>
namespace karaoke {
class PendingStereoPcm final {
public:
  void Assign(const int16_t *samples, std::size_t count) {
    samples_.assign(samples, samples + count);
    offset_ = 0;
  }
  std::size_t DrainOnce(AccompanimentSink &sink, bool paused = false) noexcept {
    if (paused || !HasPending())
      return 0;
    const auto written =
        sink.WriteStereo(samples_.data() + offset_, samples_.size() - offset_);
    offset_ += written;
    if (offset_ == samples_.size()) {
      samples_.clear();
      offset_ = 0;
    }
    return written;
  }
  bool HasPending() const noexcept { return offset_ < samples_.size(); }
  std::size_t PendingSamples() const noexcept {
    return samples_.size() - offset_;
  }
  void Reset() noexcept {
    samples_.clear();
    offset_ = 0;
  }

private:
  std::vector<int16_t> samples_;
  std::size_t offset_{0};
};
class DecoderControlMailbox final {
public:
  void Pause() noexcept {
    std::lock_guard lock(mutex_);
    paused_ = true;
    ++generation_;
  }
  void Resume() noexcept {
    std::lock_guard lock(mutex_);
    paused_ = false;
    ++generation_;
  }
  void Seek(int64_t ms) noexcept {
    std::lock_guard lock(mutex_);
    seek_ = ms;
    paused_ = false;
    ++generation_;
  }
  uint64_t Generation() const noexcept {
    std::lock_guard lock(mutex_);
    return generation_;
  }
  ResetResult ResetDisposition(uint64_t generation) const noexcept {
    std::lock_guard lock(mutex_);
    return generation == generation_ ? ResetResult::Completed
                                     : ResetResult::Superseded;
  }
  std::optional<int64_t> TakeLatestSeek() noexcept {
    std::lock_guard lock(mutex_);
    auto result = seek_;
    seek_.reset();
    return result;
  }

private:
  mutable std::mutex mutex_;
  bool paused_{true};
  uint64_t generation_{0};
  std::optional<int64_t> seek_;
};
} // namespace karaoke
#endif
