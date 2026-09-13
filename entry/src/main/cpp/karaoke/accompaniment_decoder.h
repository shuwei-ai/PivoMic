#ifndef PIVOMIC_KARAOKE_ACCOMPANIMENT_DECODER_H
#define PIVOMIC_KARAOKE_ACCOMPANIMENT_DECODER_H

#include "accompaniment_sink.h"
#include "linear_resampler.h"
#include "raw_track_policy.h"
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>

struct OH_AVSource;
struct OH_AVDemuxer;
struct OH_AVCodec;
struct OH_AVBuffer;
struct OH_AVMemory;
struct OH_AVCodecBufferAttr;

namespace karaoke {
class AccompanimentDecoder final {
public:
  enum class State { Idle, Prepared, Buffering, Running, Paused, Ended, Error };
  explicit AccompanimentDecoder(AccompanimentSink &destination, uint32_t outputRate = 48000) noexcept;
  ~AccompanimentDecoder();
  bool Prepare(int fd, int64_t offset, int64_t size);
  bool Start();
  void Pause() noexcept;
  bool Seek(int64_t milliseconds);
  void Stop() noexcept;
  void Release() noexcept;
  State GetState() const noexcept { return state_.load(); }
  int64_t DurationMs() const noexcept { return durationMs_.load(); }
  int64_t PositionMs() const noexcept { return positionMs_.load(); }
  int ErrorCode() const noexcept { return errorCode_.load(); }

  void Fail(int code) noexcept;
  void HandleCodecError(int32_t errCode) noexcept;
  void HandleNeedInputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer) noexcept;
  void HandleNewOutputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer) noexcept;
private:
  bool OpenLocked(int fd, int64_t offset, int64_t size);
  void ReleaseLocked() noexcept;
  void Worker();
  AccompanimentSink &destination_;
  uint32_t outputRate_;
  std::atomic<State> state_{State::Idle};
  std::atomic<int64_t> durationMs_{0}, positionMs_{0};
  std::atomic<int> errorCode_{0};
  std::mutex controlMutex_, workerMutex_;
  std::condition_variable wake_;
  std::thread worker_;
  std::atomic<bool> stop_{false};
  bool paused_{true};
  int64_t pendingSeekMs_{-1};
  uint64_t generation_{0};
  int ownedFd_{-1};
  uint32_t track_{0};
  OH_AVSource *source_{nullptr};
  OH_AVDemuxer *demuxer_{nullptr};
  OH_AVCodec *codec_{nullptr};
  OH_AVBuffer *rawBuffer_{nullptr};
  DecodePath decodePath_{DecodePath::Unsupported};
  int32_t rawSampleRate_{0};
  int32_t rawChannels_{0};
  LinearResampler resampler_;
};
} // namespace karaoke
#endif
