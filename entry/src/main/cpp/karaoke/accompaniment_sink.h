#ifndef PIVOMIC_KARAOKE_ACCOMPANIMENT_SINK_H
#define PIVOMIC_KARAOKE_ACCOMPANIMENT_SINK_H
#include "spsc_audio_ring.h"
#include <atomic>
#include <chrono>
#include <functional>
#include <thread>
namespace karaoke {
enum class ResetResult { Completed, Superseded, TimedOut, Error };
class AccompanimentSink {
public:
  virtual ~AccompanimentSink() = default;
  virtual std::size_t Capacity() const noexcept = 0;
  virtual std::size_t Writable() const noexcept = 0;
  virtual std::size_t WriteStereo(const int16_t *, std::size_t) noexcept = 0;
  virtual ResetResult RequestResetAndWait(std::chrono::milliseconds,
                                          const std::function<bool()> &) = 0;
};
class RingAccompanimentSink final : public AccompanimentSink {
public:
  explicit RingAccompanimentSink(std::size_t n) : ring_(n) {}
  std::size_t Writable() const noexcept override { return ring_.Writable(); }
  std::size_t Capacity() const noexcept override { return ring_.Capacity(); }
  std::size_t WriteStereo(const int16_t *p, std::size_t n) noexcept override {
    return (!p || (n & 1)) ? 0 : ring_.Write(p, n);
  }
  std::size_t ReadStereo(int16_t *p, std::size_t n) noexcept {
    return (!p || (n & 1)) ? 0 : ring_.Read(p, n);
  }
  void SetRendererActive(bool a) noexcept {
    active_.store(a, std::memory_order_release);
  }
  bool ConsumeResetOnRenderer() noexcept {
    auto r = requested_.load(std::memory_order_acquire);
    if (r == acked_.load(std::memory_order_relaxed))
      return false;
    ring_.Clear();
    acked_.store(r, std::memory_order_release);
    return true;
  }
  ResetResult RequestResetAndWait(std::chrono::milliseconds timeout,
                                  const std::function<bool()> &abort) override {
    ring_.Clear();
    if (!active_.load(std::memory_order_acquire)) {
      return ResetResult::Completed;
    }
    auto e = requested_.fetch_add(1, std::memory_order_acq_rel) + 1;
    auto deadline = std::chrono::steady_clock::now() + timeout;
    while (acked_.load(std::memory_order_acquire) < e) {
      if (abort && abort())
        return ResetResult::Superseded;
      if (std::chrono::steady_clock::now() >= deadline) {
        acked_.store(e, std::memory_order_release);
        return ResetResult::Completed;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return ResetResult::Completed;
  }

private:
  SpscAudioRing<int16_t> ring_;
  std::atomic<bool> active_{false};
  std::atomic<uint64_t> requested_{0}, acked_{0};
};
} // namespace karaoke
#endif
