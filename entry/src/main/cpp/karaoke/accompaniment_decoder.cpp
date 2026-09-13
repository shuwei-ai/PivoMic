#include "accompaniment_decoder.h"
#include "decoded_pcm_payload.h"
#include "decoder_worker_policy.h"
#include "linear_resampler.h"
#include "raw_track_policy.h"
#include <algorithm>
#include <chrono>
#include <hilog/log.h>
#include <multimedia/player_framework/native_avbuffer.h>
#include <multimedia/player_framework/native_avcodec_audiocodec.h>
#include <multimedia/player_framework/native_avdemuxer.h>
#include <multimedia/player_framework/native_avformat.h>
#include <multimedia/player_framework/native_avsource.h>
#include <multimedia/player_framework/native_avmemory.h>
#include <unistd.h>
#include <vector>

namespace karaoke {
namespace {
constexpr unsigned int kLogDomain = 0x0000;
constexpr const char *kLogTag = "PivoMicDecoder";
constexpr std::size_t kWatermark = 48000 * 2 * 2;
[[maybe_unused]] constexpr int64_t kPollUs = 10000;
constexpr auto kResetTimeout = std::chrono::milliseconds(500);

static void OnCodecError(OH_AVCodec *codec, int32_t errorCode, void *userData) {
  (void)codec;
  auto *self = static_cast<AccompanimentDecoder *>(userData);
  if (self) self->HandleCodecError(errorCode);
}

static void OnCodecStreamChanged(OH_AVCodec *codec, OH_AVFormat *format, void *userData) {
  (void)codec;
  (void)format;
  (void)userData;
}

static void OnNeedInputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer, void *userData) {
  auto *self = static_cast<AccompanimentDecoder *>(userData);
  if (self) self->HandleNeedInputBuffer(codec, index, buffer);
}

static void OnNewOutputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer, void *userData) {
  auto *self = static_cast<AccompanimentDecoder *>(userData);
  if (self) self->HandleNewOutputBuffer(codec, index, buffer);
}
} // namespace
AccompanimentDecoder::AccompanimentDecoder(AccompanimentSink &sink, uint32_t outputRate) noexcept
    : destination_(sink), outputRate_(outputRate), resampler_(outputRate) {}
AccompanimentDecoder::~AccompanimentDecoder() { Release(); }
bool AccompanimentDecoder::Prepare(int fd, int64_t offset, int64_t size) {
  std::lock_guard control(controlMutex_);
  ReleaseLocked();
  durationMs_ = 0;
  positionMs_ = 0;
  errorCode_ = 0;
  if (fd < 0 || offset < 0 || size <= 0) {
    errorCode_ = -1;
    return false;
  }
  ownedFd_ = dup(fd);
  if (ownedFd_ < 0) {
    errorCode_ = -2;
    ReleaseLocked();
    return false;
  }
  (void)lseek(ownedFd_, static_cast<off_t>(offset), SEEK_SET);
  if (!OpenLocked(ownedFd_, offset, size)) {
    ReleaseLocked();
    return false;
  }
  stop_ = false;
  if (destination_.RequestResetAndWait(kResetTimeout, [this] {
        return stop_.load();
      }) != ResetResult::Completed) {
    errorCode_ = -4;
    ReleaseLocked();
    return false;
  }
  {
    std::lock_guard worker(workerMutex_);
    paused_ = true;
    pendingSeekMs_ = -1;
    ++generation_;
  }
  state_ = State::Prepared;
  worker_ = std::thread(&AccompanimentDecoder::Worker, this);
  return true;
}
bool AccompanimentDecoder::OpenLocked(int fd, int64_t offset, int64_t size) {
  source_ = OH_AVSource_CreateWithFD(fd, offset, size);
  if (!source_) {
    errorCode_ = -20;
    return false;
  }
  OH_AVFormat *sf = OH_AVSource_GetSourceFormat(source_);
  int32_t count = 0;
  if (!sf) {
    errorCode_ = -21;
    return false;
  }
  bool got = OH_AVFormat_GetIntValue(sf, OH_MD_KEY_TRACK_COUNT, &count);
  OH_AVFormat_Destroy(sf);
  if (!got) {
    errorCode_ = -22;
    return false;
  }
  OH_AVFormat *audio = nullptr;
  for (int32_t i = 0; i < count; ++i) {
    auto *f = OH_AVSource_GetTrackFormat(source_, i);
    int32_t type = -1;
    if (f && OH_AVFormat_GetIntValue(f, OH_MD_KEY_TRACK_TYPE, &type) &&
        type == MEDIA_TYPE_AUD) {
      track_ = static_cast<uint32_t>(i);
      audio = f;
      break;
    }
    if (f)
      OH_AVFormat_Destroy(f);
  }
  if (!audio) {
    errorCode_ = -23;
    return false;
  }
  const char *mime = nullptr;
  int64_t us = 0;
  int32_t rate = 0, channels = 0, sampleFormat = 0, maxInputSize = 0;
  const bool hasDuration =
      OH_AVFormat_GetLongValue(audio, OH_MD_KEY_DURATION, &us);
  const bool hasMime =
      OH_AVFormat_GetStringValue(audio, OH_MD_KEY_CODEC_MIME, &mime);
  const bool hasRate =
      OH_AVFormat_GetIntValue(audio, OH_MD_KEY_AUD_SAMPLE_RATE, &rate);
  const bool hasChannels =
      OH_AVFormat_GetIntValue(audio, OH_MD_KEY_AUD_CHANNEL_COUNT, &channels);
  (void)OH_AVFormat_GetIntValue(audio, OH_MD_KEY_AUDIO_SAMPLE_FORMAT,
                                &sampleFormat);
  (void)OH_AVFormat_GetIntValue(audio, OH_MD_KEY_MAX_INPUT_SIZE,
                                &maxInputSize);
  if (hasDuration)
    durationMs_ = us / 1000;
  if (!hasMime || !hasRate || !hasChannels || !mime) {
    errorCode_ = -24;
    OH_AVFormat_Destroy(audio);
    return false;
  }
  std::string targetMime = mime;
  if (targetMime == "audio/mp3") {
    targetMime = "audio/mpeg";
  } else if (targetMime == "audio/x-flac") {
    targetMime = "audio/flac";
  } else if (targetMime == "audio/aac") {
    targetMime = "audio/mp4a-latm";
  }
  const AudioTrackPlan plan =
      PlanAudioTrack(targetMime.c_str(), rate, channels, sampleFormat, maxInputSize, size);
  if (plan.path == DecodePath::Unsupported) {
    errorCode_ = -30;
    OH_AVFormat_Destroy(audio);
    return false;
  }
  decodePath_ = plan.path;
  demuxer_ = OH_AVDemuxer_CreateWithSource(source_);
  if (!demuxer_) errorCode_ = -25;
  bool ok = demuxer_ != nullptr;
  if (ok && OH_AVDemuxer_SelectTrackByID(demuxer_, track_) != AV_ERR_OK) {
    errorCode_ = -27;
    ok = false;
  }
  rawSampleRate_ = plan.sampleRate > 0 ? plan.sampleRate : rate;
  rawChannels_ = plan.channels > 0 ? plan.channels : channels;
  if (ok && decodePath_ == DecodePath::RawPcm) {
    rawBuffer_ = OH_AVBuffer_Create(plan.bufferCapacity);
    if (!rawBuffer_) {
      errorCode_ = -31;
      ok = false;
    }
  } else if (ok) {
    (void)OH_AVFormat_SetIntValue(audio, OH_MD_KEY_AUDIO_SAMPLE_FORMAT,
                                  SAMPLE_S16LE);
    codec_ = ok ? OH_AudioCodec_CreateByMime(targetMime.c_str(), false) : nullptr;
    if (ok && !codec_) {
      errorCode_ = -26;
      ok = false;
    }
    if (ok) {
      OH_AVCodecCallback cb = {
          &OnCodecError, &OnCodecStreamChanged, &OnNeedInputBuffer, &OnNewOutputBuffer};
      if (OH_AudioCodec_RegisterCallback(codec_, cb, this) != AV_ERR_OK) {
        errorCode_ = -33;
        ok = false;
      }
    }
    if (ok && OH_AudioCodec_Configure(codec_, audio) != AV_ERR_OK) {
      errorCode_ = -28;
      ok = false;
    }
    if (ok && OH_AudioCodec_Prepare(codec_) != AV_ERR_OK) {
      errorCode_ = -29;
      ok = false;
    }
  }
  OH_AVFormat_Destroy(audio);
  resampler_.Reset();
  if (ok) {
    OH_LOG_Print(LOG_APP, LOG_INFO, kLogDomain, kLogTag,
                 "OpenLocked SUCCESS: mime=%{public}s, rate=%{public}d, channels=%{public}d, path=%{public}d",
                 targetMime.c_str(), rate, channels, static_cast<int>(decodePath_));
  } else {
    OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, kLogTag,
                 "OpenLocked FAILED: errorCode=%{public}d, mime=%{public}s",
                 errorCode_.load(), targetMime.c_str());
  }
  return ok;
}
bool AccompanimentDecoder::Start() {
  std::lock_guard control(controlMutex_);
  std::lock_guard worker(workerMutex_);
  if (!demuxer_ || (decodePath_ == DecodePath::Codec && !codec_) || stop_ ||
      state_ == State::Ended || state_ == State::Error)
    return false;
  paused_ = false;
  ++generation_;
  state_ = State::Buffering;
  wake_.notify_all();
  return true;
}
void AccompanimentDecoder::Pause() noexcept {
  std::lock_guard control(controlMutex_);
  std::lock_guard worker(workerMutex_);
  if (!demuxer_)
    return;
  paused_ = true;
  ++generation_;
  state_ = State::Paused;
  wake_.notify_all();
}
bool AccompanimentDecoder::Seek(int64_t ms) {
  std::lock_guard control(controlMutex_);
  std::lock_guard worker(workerMutex_);
  if (!demuxer_ || stop_ || ms < 0 ||
      (durationMs_ > 0 && ms > durationMs_))
    return false;
  pendingSeekMs_ = ms;
  paused_ = false;
  resampler_.Reset();
  ++generation_;
  state_ = State::Buffering;
  wake_.notify_all();
  return true;
}
void AccompanimentDecoder::Stop() noexcept {
  std::lock_guard control(controlMutex_);
  ReleaseLocked();
}
void AccompanimentDecoder::Release() noexcept {
  std::lock_guard control(controlMutex_);
  ReleaseLocked();
}
void AccompanimentDecoder::ReleaseLocked() noexcept {
  {
    std::lock_guard worker(workerMutex_);
    stop_ = true;
    paused_ = false;
    ++generation_;
    wake_.notify_all();
  }
  if (worker_.joinable())
    worker_.join();
  if (codec_) {
    (void)OH_AudioCodec_Stop(codec_);
    (void)OH_AudioCodec_Destroy(codec_);
    codec_ = nullptr;
  }
  if (rawBuffer_) {
    (void)OH_AVBuffer_Destroy(rawBuffer_);
    rawBuffer_ = nullptr;
  }
  if (demuxer_) {
    (void)OH_AVDemuxer_Destroy(demuxer_);
    demuxer_ = nullptr;
  }
  if (source_) {
    (void)OH_AVSource_Destroy(source_);
    source_ = nullptr;
  }
  if (ownedFd_ >= 0) {
    close(ownedFd_);
    ownedFd_ = -1;
  }
  decodePath_ = DecodePath::Unsupported;
  rawSampleRate_ = 0;
  rawChannels_ = 0;
  resampler_.Reset();
  state_ = State::Idle;
}
void AccompanimentDecoder::Fail(int code) noexcept {
  errorCode_ = code;
  state_ = State::Error;
  OH_LOG_Print(LOG_APP, LOG_ERROR, kLogDomain, kLogTag,
               "AccompanimentDecoder Fail event: errorCode=%{public}d", code);
  std::lock_guard worker(workerMutex_);
  paused_ = true;
  wake_.notify_all();
}

void AccompanimentDecoder::HandleCodecError(int32_t errCode) noexcept {
  Fail(errCode);
}

void AccompanimentDecoder::HandleNeedInputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer) noexcept {
  if (!codec || !buffer) return;
  if (!demuxer_ || stop_ || state_ == State::Ended || state_ == State::Error) {
    OH_AVCodecBufferAttr attr{};
    attr.flags = AVCODEC_BUFFER_FLAGS_EOS;
    attr.size = 0;
    attr.pts = 0;
    OH_AVBuffer_SetBufferAttr(buffer, &attr);
    (void)OH_AudioCodec_PushInputBuffer(codec, index);
    return;
  }
  {
    std::unique_lock lock(workerMutex_);
    while (paused_ && !stop_ && pendingSeekMs_ < 0) {
      wake_.wait(lock);
    }
    if (stop_ || !demuxer_ || state_ == State::Ended || state_ == State::Error) {
      OH_AVCodecBufferAttr attr{};
      attr.flags = AVCODEC_BUFFER_FLAGS_EOS;
      attr.size = 0;
      attr.pts = 0;
      OH_AVBuffer_SetBufferAttr(buffer, &attr);
      (void)OH_AudioCodec_PushInputBuffer(codec, index);
      return;
    }
  }
  auto read = OH_AVDemuxer_ReadSampleBuffer(demuxer_, track_, buffer);
  if (read != AV_ERR_OK) {
    OH_AVCodecBufferAttr attr{};
    attr.flags |= AVCODEC_BUFFER_FLAGS_EOS;
    attr.size = 0;
    attr.pts = 0;
    OH_AVBuffer_SetBufferAttr(buffer, &attr);
    (void)OH_AudioCodec_PushInputBuffer(codec, index);
    return;
  }
  auto pushRes = OH_AudioCodec_PushInputBuffer(codec, index);
  if (pushRes != AV_ERR_OK) {
    std::lock_guard lock(workerMutex_);
    if (!stop_ && state_ != State::Error && state_ != State::Ended && pendingSeekMs_ < 0) {
      Fail(-15);
    }
  }
}

void AccompanimentDecoder::HandleNewOutputBuffer(OH_AVCodec *codec, uint32_t index, OH_AVBuffer *buffer) noexcept {
  if (!buffer || stop_ || state_ == State::Error) {
    if (codec) (void)OH_AudioCodec_FreeOutputBuffer(codec, index);
    return;
  }
  OH_AVCodecBufferAttr attr{};
  if (OH_AVBuffer_GetBufferAttr(buffer, &attr) != AV_ERR_OK) {
    (void)OH_AudioCodec_FreeOutputBuffer(codec, index);
    Fail(-17);
    return;
  }
  const bool outputEos = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
  const int32_t cap = OH_AVBuffer_GetCapacity(buffer);
  uint8_t *addr = OH_AVBuffer_GetAddr(buffer);
  if (attr.size > 0 && addr != nullptr && !stop_ && state_ != State::Error) {
    int32_t rate = rawSampleRate_ > 0 ? rawSampleRate_ : 44100;
    int32_t channels = rawChannels_ > 0 ? rawChannels_ : 2;
    auto *fmt = OH_AudioCodec_GetOutputDescription(codec);
    if (fmt) {
      int32_t r = 0, c = 0;
      if (OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_AUD_SAMPLE_RATE, &r) && r > 0) rate = r;
      if (OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_AUD_CHANNEL_COUNT, &c) && c > 0) channels = c;
      OH_AVFormat_Destroy(fmt);
    }
    bool valid = (channels == 1 || channels == 2) && rate > 0;
    DecodedPcmPayload payload =
        valid ? DecodePcmPayload(addr, cap, attr.offset, attr.size,
                                 static_cast<uint32_t>(channels), outputEos)
              : DecodedPcmPayload{};
    if (valid && payload.kind == DecodedPayloadKind::Pcm) {
      const int16_t *pcm = payload.samples.data();
      std::size_t frames = payload.Frames(static_cast<uint32_t>(channels));
      if (frames > 0) {
        std::vector<int16_t> converted(frames * 4 + 1024);
        auto rr = resampler_.Process(pcm, frames, rate, channels, converted.data(), converted.size() / 2);
        if (rr.ok && rr.producedFrames > 0) {
          PendingStereoPcm pending;
          pending.Assign(converted.data(), rr.producedFrames * 2);
          while (pending.HasPending()) {
            if (pending.DrainOnce(destination_) != 0) {
              continue;
            }
            std::unique_lock lock(workerMutex_);
            if (stop_ || state_ == State::Error || pendingSeekMs_ >= 0 || paused_) {
              pending.Reset();
              break;
            }
            wake_.wait_for(lock, std::chrono::milliseconds(5), [&] {
              return stop_ || state_ == State::Error || pendingSeekMs_ >= 0 || paused_;
            });
          }
        }
      }
      positionMs_ = attr.pts / 1000;
      if (state_ == State::Buffering) state_ = State::Running;
    }
  }
  if (outputEos) {
    state_ = State::Ended;
    std::lock_guard lock(workerMutex_);
    paused_ = true;
  }
  (void)OH_AudioCodec_FreeOutputBuffer(codec, index);
}
void AccompanimentDecoder::Worker() {
  LinearResampler resampler(outputRate_);
  std::vector<int16_t> converted(16384);
  PendingStereoPcm pending;
  bool started = false, inputEos = false, codecFlushed = false;
  auto consume = [&](DecodedPcmPayload payload, int32_t rate,
                     int32_t channels, int64_t pts, bool outputEos,
                     uint64_t &cycle) {
    if (payload.kind == DecodedPayloadKind::EndOfStream) {
      state_ = State::Ended;
      std::lock_guard lock(workerMutex_);
      paused_ = true;
      return;
    }
    if (payload.kind != DecodedPayloadKind::Pcm) {
      Fail(-17);
      return;
    }
    const int16_t *pcm = payload.samples.data();
    std::size_t frames = payload.Frames(static_cast<uint32_t>(channels));
    bool interrupted = false;
    while (frames && !interrupted) {
      auto rr = resampler.Process(pcm, frames, rate, channels, converted.data(),
                                  converted.size() / 2);
      if (!rr.ok) {
        Fail(-18);
        interrupted = true;
        break;
      }
      pcm += rr.consumedFrames * channels;
      frames -= rr.consumedFrames;
      pending.Assign(converted.data(), rr.producedFrames * 2);
      while (pending.HasPending()) {
        {
          std::unique_lock lock(workerMutex_);
          while (paused_ && !stop_ && pendingSeekMs_ < 0)
            wake_.wait(lock);
          if (stop_ || pendingSeekMs_ >= 0) {
            pending.Reset();
            interrupted = true;
            break;
          }
        }
        if (pending.DrainOnce(destination_) != 0)
          continue;
        std::unique_lock lock(workerMutex_);
        wake_.wait_for(lock, std::chrono::milliseconds(5),
                       [&] { return stop_ || paused_ || pendingSeekMs_ >= 0; });
        while (paused_ && !stop_ && pendingSeekMs_ < 0)
          wake_.wait(lock);
        if (stop_ || pendingSeekMs_ >= 0) {
          pending.Reset();
          interrupted = true;
          break;
        }
        cycle = generation_;
      }
      if (rr.consumedFrames == 0 && rr.producedFrames == 0)
        break;
    }
    if (interrupted)
      return;
    positionMs_ = pts / 1000;
    if (state_ == State::Buffering &&
        destination_.Capacity() - destination_.Writable() >=
            std::min(kWatermark, destination_.Capacity()))
      state_ = State::Running;
    if (outputEos) {
      state_ = State::Ended;
      std::lock_guard lock(workerMutex_);
      paused_ = true;
    }
  };
  for (;;) {
    uint64_t cycle = 0;
    int64_t seek = -1;
    {
      std::unique_lock lock(workerMutex_);
      wake_.wait(lock, [&] { return stop_ || !paused_; });
      if (stop_)
        break;
      cycle = generation_;
      seek = pendingSeekMs_;
      pendingSeekMs_ = -1;
    }
    if (!started) {
      if (decodePath_ == DecodePath::Codec &&
          OH_AudioCodec_Start(codec_) != AV_ERR_OK) {
        Fail(-10);
        break;
      }
      started = true;
    }
    if (seek >= 0) {
      pending.Reset();
      if ((decodePath_ == DecodePath::Codec && !codecFlushed &&
           OH_AudioCodec_Flush(codec_) != AV_ERR_OK) ||
          OH_AVDemuxer_SeekToTime(demuxer_, seek, SEEK_MODE_PREVIOUS_SYNC) !=
              AV_ERR_OK) {
        Fail(-11);
        continue;
      }
      codecFlushed = true;
      const ResetResult reset =
          destination_.RequestResetAndWait(kResetTimeout, [&] {
            std::lock_guard lock(workerMutex_);
            return stop_ || paused_ || generation_ != cycle;
          });
      if (reset == ResetResult::Superseded) {
        std::lock_guard lock(workerMutex_);
        if (stop_)
          break;
        if (pendingSeekMs_ < 0)
          pendingSeekMs_ = seek;
        continue;
      }
      if (reset != ResetResult::Completed) {
        Fail(-11);
        continue;
      }
      codecFlushed = false;
      if (decodePath_ == DecodePath::Codec) {
        (void)OH_AudioCodec_Start(codec_);
      }
      resampler.Reset();
      positionMs_ = seek;
      inputEos = false;
    }
    if (decodePath_ == DecodePath::RawPcm) {
      const auto read =
          OH_AVDemuxer_ReadSampleBuffer(demuxer_, track_, rawBuffer_);
      OH_AVCodecBufferAttr attr{};
      if (read != AV_ERR_OK ||
          OH_AVBuffer_GetBufferAttr(rawBuffer_, &attr) != AV_ERR_OK) {
        Fail(read == AV_ERR_OK ? -13 : -32);
        break;
      }
      const bool eos = (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) != 0;
      const auto payload = DecodePcmPayload(
          OH_AVBuffer_GetAddr(rawBuffer_), OH_AVBuffer_GetCapacity(rawBuffer_),
          attr.offset, attr.size, static_cast<uint32_t>(rawChannels_), eos);
      consume(payload, rawSampleRate_, rawChannels_, attr.pts, eos, cycle);
      if (state_ == State::Error)
        break;
      continue;
    }
    if (decodePath_ == DecodePath::Codec) {
      (void)inputEos;
      std::unique_lock lock(workerMutex_);
      wake_.wait_for(lock, std::chrono::milliseconds(20), [&] {
        return stop_ || paused_ || pendingSeekMs_ >= 0;
      });
      continue;
    }
  }
}
} // namespace karaoke
