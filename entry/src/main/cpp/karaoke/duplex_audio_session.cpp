#include "duplex_audio_session.h"

#include "audio_capability_probe.h"
#include "accompaniment_reference_ring.h"
#include "accompaniment_sink.h"
#include "realtime_mixer.h"
#include "spsc_audio_ring.h"
#include "microphone_backlog_policy.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <thread>

#ifdef __OHOS__
#include <hilog/log.h>
#include <ohaudio/native_audiocapturer.h>
#include <ohaudio/native_audiorenderer.h>
#include <ohaudio/native_audiostreambuilder.h>
#endif

namespace karaoke {

#ifdef __OHOS__
namespace {
constexpr unsigned int kAudioDiagDomain = 0x0000;
constexpr const char *kAudioDiagTag = "PivoMicAudioDiag";
constexpr std::uint64_t kAudioDiagIntervalCallbacks = 100;
}
#endif

void CallbackLifetimeGate::Open() noexcept
{
    std::uint64_t expected = kClosed;
    (void)state_.compare_exchange_strong(expected, 0, std::memory_order_release, std::memory_order_relaxed);
}
void CallbackLifetimeGate::Close() noexcept { state_.fetch_or(kClosed, std::memory_order_acq_rel); }
bool CallbackLifetimeGate::Enter() noexcept
{
    std::uint64_t current = state_.load(std::memory_order_acquire);
    for (;;) {
        if ((current & kClosed) != 0 || (current & kActiveMask) == kActiveMask) return false;
        if (state_.compare_exchange_weak(current, current + 1,
                std::memory_order_acq_rel, std::memory_order_acquire)) return true;
    }
}
void CallbackLifetimeGate::Leave() noexcept { state_.fetch_sub(1, std::memory_order_acq_rel); }
void CallbackLifetimeGate::Drain() const noexcept
{
    while ((state_.load(std::memory_order_acquire) & kActiveMask) != 0) std::this_thread::yield();
}
std::uint32_t CallbackLifetimeGate::Active() const noexcept
{
    return static_cast<std::uint32_t>(state_.load(std::memory_order_acquire) & kActiveMask);
}
bool CallbackLifetimeGate::IsClosed() const noexcept
{
    return (state_.load(std::memory_order_acquire) & kClosed) != 0;
}

#ifdef __OHOS__
namespace {

class NativeReleaseQuarantine final {
public:
    bool TryReserveForSession() noexcept
    {
        std::lock_guard<std::mutex> lock(mutex_);
        RetryLocked();
        return state_.TryReserveForSession();
    }

    void ReleaseReservation() noexcept
    {
        std::lock_guard<std::mutex> lock(mutex_);
        state_.ReleaseReservation();
    }

    void Retain(std::unique_ptr<CallbackTargetBridge> bridge,
        OH_AudioRenderer *renderer, OH_AudioCapturer *capturer) noexcept
    {
        std::lock_guard<std::mutex> lock(mutex_);
        bridge_ = std::move(bridge);
        renderer_ = renderer;
        capturer_ = capturer;
        state_.RetainFailedHandles(renderer_ != nullptr, capturer_ != nullptr);
    }

private:
    void RetryLocked() noexcept
    {
        if (!bridge_ && renderer_ == nullptr && capturer_ == nullptr) return;
        bool rendererReleased = renderer_ == nullptr;
        bool capturerReleased = capturer_ == nullptr;
        if (renderer_ != nullptr) {
            rendererReleased = OH_AudioRenderer_Release(renderer_) == AUDIOSTREAM_SUCCESS;
            if (rendererReleased) renderer_ = nullptr;
        }
        if (capturer_ != nullptr) {
            capturerReleased = OH_AudioCapturer_Release(capturer_) == AUDIOSTREAM_SUCCESS;
            if (capturerReleased) capturer_ = nullptr;
        }
        if (bridge_) bridge_->Drain();
        if (state_.Retry(rendererReleased, capturerReleased)) bridge_.reset();
    }

    std::mutex mutex_;
    BoundedReleaseQuarantineState state_;
    std::unique_ptr<CallbackTargetBridge> bridge_;
    OH_AudioRenderer *renderer_ {nullptr};
    OH_AudioCapturer *capturer_ {nullptr};
};

NativeReleaseQuarantine &ReleaseQuarantine() noexcept
{
    // Process-lifetime by design: static destruction must not invalidate callback userData
    // for a platform handle that has persistently rejected Release.
    static NativeReleaseQuarantine *quarantine = new NativeReleaseQuarantine();
    return *quarantine;
}

} // namespace
#endif

SessionState DuplexSessionLifecycle::State() const noexcept { return state_; }

bool DuplexSessionLifecycle::Prepare() noexcept
{
    if (state_ != SessionState::Idle) return false;
    state_ = SessionState::Preparing;
    return true;
}

bool DuplexSessionLifecycle::MarkReady() noexcept
{
    if (state_ != SessionState::Preparing) return false;
    state_ = SessionState::Ready;
    return true;
}

bool DuplexSessionLifecycle::Start(bool aecSupported, bool headphonesConnected) noexcept
{
    if (state_ != SessionState::Ready || !DuplexSafetyPolicy::CanMonitor(aecSupported, headphonesConnected)) {
        return false;
    }
    state_ = SessionState::Singing;
    return true;
}

bool DuplexSessionLifecycle::Pause() noexcept
{
    if (state_ != SessionState::Singing) return false;
    state_ = SessionState::Paused;
    return true;
}

bool DuplexSessionLifecycle::Resume() noexcept
{
    if (state_ != SessionState::Paused && state_ != SessionState::Interrupted) return false;
    state_ = SessionState::Singing;
    return true;
}

bool DuplexSessionLifecycle::Stop() noexcept
{
    state_ = SessionState::Idle;
    return true;
}

void DuplexSessionLifecycle::NotifyInterrupted() noexcept { state_ = SessionState::Interrupted; }
void DuplexSessionLifecycle::NotifyError() noexcept { state_ = SessionState::Error; }
void DuplexSessionLifecycle::ApplyHaltOutcome(DuplexControlAction action) noexcept
{
    if (action == DuplexControlAction::HaltForError) {
        NotifyError();
    } else if ((action == DuplexControlAction::HaltForInterruption ||
                action == DuplexControlAction::PauseForInterruption) && state_ != SessionState::Error) {
        NotifyInterrupted();
    } else if (action == DuplexControlAction::ResumeFromInterruption && state_ == SessionState::Interrupted) {
        state_ = SessionState::Singing;
    }
}

struct DuplexAudioSession::Impl {
    static constexpr std::size_t kCallbackFrames = 240;
    static constexpr std::size_t kRingFrames = 48000 * 4;

    DuplexSessionLifecycle lifecycle;
    SpscAudioRing<std::int16_t> micRing {kRingFrames};
    RingAccompanimentSink accompanimentSink {kRingFrames * 2};
    AccompanimentReferenceRing referenceRing {kRingFrames * 2};
    RealtimeMixer mixer {48000, kCallbackFrames};
    std::atomic<bool> callbackError {false};
    std::atomic<bool> callbackInterrupted {false};
    std::atomic<AudioInterruptHint> lastInterruptHint {AudioInterruptHint::None};
    std::atomic<bool> resumeRequested {false};
    std::atomic<bool> isDucked {false};
    std::atomic<bool> callbackDeviceChanged {false};
    std::unique_ptr<CallbackTargetBridge> callbackBridge {std::make_unique<CallbackTargetBridge>()};
    NativeReleaseTracker releaseTracker;
    std::atomic<bool> releaseStarted {false};
    std::atomic<bool> releaseComplete {false};
    std::atomic<std::uint64_t> renderedFrames {0};
    std::atomic<std::uint64_t> underruns {0};
    std::uint64_t diagnosticWriteCallbacks {0};
    std::atomic<std::uint64_t> diagnosticReadCallbacks {0};
    std::atomic<std::uint64_t> micOverflowFrames {0};
    std::uint64_t micDiscardedFrames {0}; // Renderer callback owns this counter.
    std::atomic<std::int32_t> lastHwMicPeak {0};
    bool fastMode {false};
    bool aecSupported {false};
    bool deviceChanged {false};
#ifdef __OHOS__
    OH_AudioCapturer *capturer {nullptr};
    OH_AudioRenderer *renderer {nullptr};
    bool nativeReservationHeld {false};
#endif

    Impl() { callbackBridge->Attach(this); }

    struct CallbackScope {
        explicit CallbackScope(CallbackTargetBridge &bridge)
            : bridge_(bridge)
        {
            void *target = nullptr;
            entered_ = bridge_.Enter(&target);
            target_ = static_cast<Impl *>(target);
        }
        ~CallbackScope() { if (entered_) bridge_.Leave(); }
        [[nodiscard]] Impl *Target() const noexcept { return target_; }
        CallbackTargetBridge &bridge_;
        Impl *target_ {nullptr};
        bool entered_ {false};
    };

#ifdef __OHOS__
    static void ReadData(OH_AudioCapturer *, void *userData, void *audioData, int32_t audioDataSize)
    {
        CallbackScope scope(*static_cast<CallbackTargetBridge *>(userData));
        Impl *self = scope.Target();
        if (self == nullptr || audioData == nullptr || audioDataSize <= 0) return;
        const auto sampleCount = static_cast<std::size_t>(audioDataSize) / sizeof(std::int16_t);
        const auto *pcm = static_cast<const std::int16_t *>(audioData);
        std::int32_t peak = 0;
        for (std::size_t i = 0; i < sampleCount; ++i) {
            peak = std::max(peak, std::abs(static_cast<std::int32_t>(pcm[i])));
        }
        self->lastHwMicPeak.store(peak, std::memory_order_relaxed);
        self->diagnosticReadCallbacks.fetch_add(1, std::memory_order_relaxed);
        const std::size_t written = self->micRing.Write(pcm, sampleCount);
        self->micOverflowFrames.fetch_add(sampleCount - written, std::memory_order_relaxed);
    }

    static OH_AudioData_Callback_Result WriteData(
        OH_AudioRenderer *, void *userData, void *audioData, int32_t audioDataSize)
    {
        CallbackScope scope(*static_cast<CallbackTargetBridge *>(userData));
        Impl *self = scope.Target();
        if (audioData == nullptr || audioDataSize <= 0) return AUDIO_DATA_CALLBACK_RESULT_INVALID;
        std::memset(audioData, 0, static_cast<std::size_t>(audioDataSize));
        if (self == nullptr) return AUDIO_DATA_CALLBACK_RESULT_VALID;

        auto *output = static_cast<std::int16_t *>(audioData);
        self->accompanimentSink.ConsumeResetOnRenderer();
        const std::size_t frames = static_cast<std::size_t>(audioDataSize) / (2 * sizeof(std::int16_t));
        const std::size_t micQueuedBefore = self->micRing.Readable();
        self->micDiscardedFrames += TrimMicrophoneBacklog(self->micRing, frames);
        std::array<std::int16_t, kCallbackFrames> mic {};
        std::array<std::int16_t, kCallbackFrames * 2> music {};
        std::int32_t micPeak = 0;
        std::int32_t musicPeak = 0;
        std::size_t totalMicRead = 0;
        std::size_t totalMusicRead = 0;
        std::size_t offset = 0;
        while (offset < frames) {
            const std::size_t block = std::min(kCallbackFrames, frames - offset);
            const std::size_t micRead = self->micRing.Read(mic.data(), block);
            const std::size_t musicRead = self->accompanimentSink.ReadStereo(music.data(), block * 2);
            totalMicRead += micRead;
            totalMusicRead += musicRead;
            for (std::size_t i = 0; i < micRead; ++i) {
                micPeak = std::max(micPeak, std::abs(static_cast<std::int32_t>(mic[i])));
            }
            for (std::size_t i = 0; i < musicRead; ++i) {
                musicPeak = std::max(musicPeak, std::abs(static_cast<std::int32_t>(music[i])));
            }
            self->referenceRing.WriteReferenceStereo(music.data(), musicRead);
            std::fill(mic.begin() + static_cast<std::ptrdiff_t>(micRead), mic.begin() + static_cast<std::ptrdiff_t>(block), 0);
            std::fill(music.begin() + static_cast<std::ptrdiff_t>(musicRead),
                music.begin() + static_cast<std::ptrdiff_t>(block * 2), 0);
            if (micRead != block || musicRead != block * 2) {
                self->underruns.fetch_add(1, std::memory_order_relaxed);
            }
            if (self->isDucked.load(std::memory_order_relaxed)) {
                for (std::size_t i = 0; i < block * 2; ++i) {
                    music[i] = static_cast<std::int16_t>(music[i] * 0.2f);
                }
            }
            self->mixer.Process(music.data(), mic.data(), output + offset * 2, block);
            offset += block;
        }
        self->renderedFrames.fetch_add(frames, std::memory_order_relaxed);
        ++self->diagnosticWriteCallbacks;
        if (self->diagnosticWriteCallbacks % kAudioDiagIntervalCallbacks == 0) {
            std::int32_t outputPeak = 0;
            for (std::size_t i = 0; i < frames * 2; ++i) {
                outputPeak = std::max(outputPeak, std::abs(static_cast<std::int32_t>(output[i])));
            }
            const auto metrics = self->mixer.GetStageMetrics();
            OH_LOG_Print(LOG_APP, LOG_INFO, kAudioDiagDomain, kAudioDiagTag,
                "[PivoMicChain] cb[w=%{public}llu,r=%{public}llu] hwMicPeak=%{public}d "
                "read[mic=%{public}zu,mus=%{public}zu] peak[mic=%{public}d,mus=%{public}d,out=%{public}d] "
                "stages[raw=%{public}.3f,shift=%{public}.3f,dyn=%{public}.3f,wet=%{public}.3f,vSub=%{public}.3f,mSub=%{public}.3f,out=%{public}.3f] "
                "gate=%{public}.2f gains[vocal=%{public}.2f,effVocal=%{public}.2f,mus=%{public}.2f] underruns=%{public}llu "
                "micQueue[beforeMs=%{public}zu,afterMs=%{public}zu,discardedFrames=%{public}llu,overflowFrames=%{public}llu]",
                static_cast<unsigned long long>(self->diagnosticWriteCallbacks),
                static_cast<unsigned long long>(self->diagnosticReadCallbacks.load(std::memory_order_relaxed)),
                self->lastHwMicPeak.load(std::memory_order_relaxed),
                totalMicRead, totalMusicRead, micPeak, musicPeak, outputPeak,
                metrics.rawPeak, metrics.shiftPeak, metrics.dynPeak, metrics.wetPeak,
                metrics.vocalSubPeak, metrics.musicSubPeak, metrics.masterPeak,
                metrics.gateGain, self->mixer.VocalGain(), metrics.effectiveVocalGain, self->mixer.AccompanimentGain(),
                static_cast<unsigned long long>(self->underruns.load(std::memory_order_relaxed)),
                micQueuedBefore / 48, self->micRing.Readable() / 48,
                static_cast<unsigned long long>(self->micDiscardedFrames),
                static_cast<unsigned long long>(self->micOverflowFrames.load(std::memory_order_relaxed)));
        }
        return AUDIO_DATA_CALLBACK_RESULT_VALID;
    }

#ifdef __OHOS__
    static AudioInterruptHint MapInterruptHint(OH_AudioInterrupt_Hint hint) noexcept
    {
        switch (hint) {
            case AUDIOSTREAM_INTERRUPT_HINT_RESUME: return AudioInterruptHint::Resume;
            case AUDIOSTREAM_INTERRUPT_HINT_PAUSE: return AudioInterruptHint::Pause;
            case AUDIOSTREAM_INTERRUPT_HINT_STOP: return AudioInterruptHint::Stop;
            case AUDIOSTREAM_INTERRUPT_HINT_DUCK: return AudioInterruptHint::Duck;
            case AUDIOSTREAM_INTERRUPT_HINT_UNDUCK: return AudioInterruptHint::Unduck;
            default: return AudioInterruptHint::None;
        }
    }

    static void Interrupted(OH_AudioRenderer *, void *userData, OH_AudioInterrupt_ForceType,
        OH_AudioInterrupt_Hint hint)
    {
        CallbackScope scope(*static_cast<CallbackTargetBridge *>(userData));
        if (Impl *self = scope.Target()) {
            self->lastInterruptHint.store(MapInterruptHint(hint), std::memory_order_release);
            self->callbackInterrupted.store(true, std::memory_order_release);
        }
    }
    static void CaptureInterrupted(OH_AudioCapturer *, void *userData, OH_AudioInterrupt_ForceType,
        OH_AudioInterrupt_Hint hint)
    {
        CallbackScope scope(*static_cast<CallbackTargetBridge *>(userData));
        if (Impl *self = scope.Target()) {
            self->lastInterruptHint.store(MapInterruptHint(hint), std::memory_order_release);
            self->callbackInterrupted.store(true, std::memory_order_release);
        }
    }
#endif
    static void RendererError(OH_AudioRenderer *, void *userData, OH_AudioStream_Result)
    {
        CallbackScope scope(*static_cast<CallbackTargetBridge *>(userData));
        if (Impl *self = scope.Target()) self->callbackError.store(true, std::memory_order_release);
    }
    static void CapturerError(OH_AudioCapturer *, void *userData, OH_AudioStream_Result)
    {
        CallbackScope scope(*static_cast<CallbackTargetBridge *>(userData));
        if (Impl *self = scope.Target()) self->callbackError.store(true, std::memory_order_release);
    }
    static void OutputChanged(OH_AudioRenderer *, void *userData, OH_AudioStream_DeviceChangeReason)
    {
        CallbackScope scope(*static_cast<CallbackTargetBridge *>(userData));
        if (Impl *self = scope.Target()) self->callbackDeviceChanged.store(true, std::memory_order_release);
    }
    static void InputChanged(OH_AudioCapturer *, void *userData, OH_AudioDeviceDescriptorArray *)
    {
        CallbackScope scope(*static_cast<CallbackTargetBridge *>(userData));
        if (Impl *self = scope.Target()) self->callbackDeviceChanged.store(true, std::memory_order_release);
    }

    static bool Configure(OH_AudioStreamBuilder *builder, int channels, OH_AudioStream_LatencyMode latency) noexcept
    {
        return OH_AudioStreamBuilder_SetSamplingRate(builder, 48000) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetChannelCount(builder, channels) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetSampleFormat(builder, AUDIOSTREAM_SAMPLE_S16LE) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetEncodingType(builder, AUDIOSTREAM_ENCODING_TYPE_RAW) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_SetLatencyMode(builder, latency) == AUDIOSTREAM_SUCCESS;
    }

    bool Generate(OH_AudioStream_LatencyMode latency) noexcept
    {
        OH_AudioStreamBuilder *captureBuilder = nullptr;
        OH_AudioStreamBuilder *renderBuilder = nullptr;
        bool ok = OH_AudioStreamBuilder_Create(&captureBuilder, AUDIOSTREAM_TYPE_CAPTURER) == AUDIOSTREAM_SUCCESS &&
            OH_AudioStreamBuilder_Create(&renderBuilder, AUDIOSTREAM_TYPE_RENDERER) == AUDIOSTREAM_SUCCESS;
        if (ok) {
            const bool speakerRoute = mixer.AudioRoute() == AudioRouteMode::Speaker;
            const OH_AudioStream_SourceType sourceType = AUDIOSTREAM_SOURCE_TYPE_MIC;
            const OH_AudioStream_Usage rendererUsage = AUDIOSTREAM_USAGE_MUSIC;
            OH_LOG_Print(LOG_APP, LOG_INFO, kAudioDiagDomain, kAudioDiagTag,
                "[PivoMicAudioDiag] buildStreams route=%{public}u usage=%{public}d profile=%{public}s latency=%{public}d",
                static_cast<unsigned int>(mixer.AudioRoute()), static_cast<int>(rendererUsage),
                speakerRoute ? "speaker_music_render" : "headset_music_render", static_cast<int>(latency));
            ok = Configure(captureBuilder, 1, latency) && Configure(renderBuilder, 2, latency) &&
                OH_AudioStreamBuilder_SetCapturerInfo(captureBuilder, sourceType) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_SetRendererInfo(renderBuilder, rendererUsage) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_SetCapturerReadDataCallback(captureBuilder, ReadData, callbackBridge.get()) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_SetCapturerInterruptCallback(captureBuilder, CaptureInterrupted, callbackBridge.get()) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_SetCapturerErrorCallback(captureBuilder, CapturerError, callbackBridge.get()) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_SetCapturerDeviceChangeCallback(captureBuilder, InputChanged, callbackBridge.get()) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_SetRendererWriteDataCallback(renderBuilder, WriteData, callbackBridge.get()) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_SetRendererInterruptCallback(renderBuilder, Interrupted, callbackBridge.get()) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_SetRendererErrorCallback(renderBuilder, RendererError, callbackBridge.get()) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_SetRendererOutputDeviceChangeCallback(renderBuilder, OutputChanged, callbackBridge.get()) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_GenerateCapturer(captureBuilder, &capturer) == AUDIOSTREAM_SUCCESS &&
                OH_AudioStreamBuilder_GenerateRenderer(renderBuilder, &renderer) == AUDIOSTREAM_SUCCESS;
        }
        if (captureBuilder != nullptr) OH_AudioStreamBuilder_Destroy(captureBuilder);
        if (renderBuilder != nullptr) OH_AudioStreamBuilder_Destroy(renderBuilder);
        releaseTracker.SetLiveHandles(renderer != nullptr, capturer != nullptr);
        if (ok && latency == AUDIOSTREAM_LATENCY_MODE_FAST) {
            OH_AudioStream_FastStatus captureStatus = AUDIOSTREAM_FASTSTATUS_NORMAL;
            OH_AudioStream_FastStatus renderStatus = AUDIOSTREAM_FASTSTATUS_NORMAL;
            ok = OH_AudioCapturer_GetFastStatus(capturer, &captureStatus) == AUDIOSTREAM_SUCCESS &&
                OH_AudioRenderer_GetFastStatus(renderer, &renderStatus) == AUDIOSTREAM_SUCCESS &&
                captureStatus == AUDIOSTREAM_FASTSTATUS_FAST && renderStatus == AUDIOSTREAM_FASTSTATUS_FAST;
        }
        if (!ok) (void)ReleaseStreams();
        return ok;
    }

    [[nodiscard]] bool ReleaseStreams() noexcept
    {
        bool rendererReleased = renderer == nullptr;
        bool capturerReleased = capturer == nullptr;
        if (renderer != nullptr) {
            rendererReleased = OH_AudioRenderer_Release(renderer) == AUDIOSTREAM_SUCCESS;
            if (rendererReleased) renderer = nullptr;
        }
        if (capturer != nullptr) {
            capturerReleased = OH_AudioCapturer_Release(capturer) == AUDIOSTREAM_SUCCESS;
            if (capturerReleased) capturer = nullptr;
        }
        const bool complete = releaseTracker.ApplyResults(rendererReleased, capturerReleased);
        DrainCallbacks();
        return complete;
    }

    void QuarantineFailedStreams() noexcept
    {
        callbackBridge->Close();
        callbackBridge->Drain();
        callbackBridge->Detach();
        ReleaseQuarantine().Retain(std::move(callbackBridge), renderer, capturer);
        renderer = nullptr;
        capturer = nullptr;
        (void)releaseTracker.ApplyResults(true, true);
        nativeReservationHeld = false;
    }
#endif

    void DrainCallbacks() noexcept
    {
        // Control-thread only. Once closed, entrants return immediately and in-flight callbacks
        // contain no blocking operations, so waiting is finite in a healthy audio service.
        callbackBridge->Drain();
    }

    void HaltAndReset() noexcept
    {
#ifdef __OHOS__
        if (renderer != nullptr) {
            OH_AudioStream_State state = AUDIOSTREAM_STATE_INVALID;
            if (OH_AudioRenderer_GetCurrentState(renderer, &state) == AUDIOSTREAM_SUCCESS) {
                if (state == AUDIOSTREAM_STATE_RUNNING || state == AUDIOSTREAM_STATE_PAUSED) {
                    OH_AudioRenderer_Stop(renderer);
                }
            }
        }
        if (capturer != nullptr) {
            OH_AudioStream_State state = AUDIOSTREAM_STATE_INVALID;
            if (OH_AudioCapturer_GetCurrentState(capturer, &state) == AUDIOSTREAM_SUCCESS) {
                if (state == AUDIOSTREAM_STATE_RUNNING || state == AUDIOSTREAM_STATE_PAUSED) {
                    OH_AudioCapturer_Stop(capturer);
                }
            }
        }
#endif
        callbackBridge->Close();
        DrainCallbacks();
        micRing.Clear();
        referenceRing.Clear();
        accompanimentSink.SetRendererActive(false);
        (void)accompanimentSink.RequestResetAndWait(std::chrono::milliseconds(0), {});
        mixer.Reset();
    }
};

DuplexAudioSession::DuplexAudioSession() : impl_(std::make_unique<Impl>()) {}
DuplexAudioSession::~DuplexAudioSession()
{
    if (!Release() && impl_ && impl_->releaseTracker.MustRetainCallbackContext()) {
#ifdef __OHOS__
        // Detach the large session state. Only the tiny callback bridge and failed handles survive,
        // in the process-wide single-slot quarantine retried before any future stream creation.
        impl_->QuarantineFailedStreams();
#endif
    }
}

bool DuplexAudioSession::Prepare() noexcept
{
    if (!impl_ || impl_->releaseStarted.load(std::memory_order_acquire) || !impl_->lifecycle.Prepare()) return false;
    impl_->aecSupported = AudioCapabilityProbe::Probe().aecSupported;
#ifdef __OHOS__
    if (!ReleaseQuarantine().TryReserveForSession()) {
        impl_->lifecycle.NotifyError();
        return false;
    }
    impl_->nativeReservationHeld = true;
    impl_->fastMode = impl_->Generate(AUDIOSTREAM_LATENCY_MODE_FAST);
    if (!impl_->fastMode && (!impl_->releaseTracker.CanBuildFallback() ||
        !impl_->Generate(AUDIOSTREAM_LATENCY_MODE_NORMAL))) {
        impl_->lifecycle.NotifyError();
        if (impl_->releaseTracker.CanBuildFallback()) {
            ReleaseQuarantine().ReleaseReservation();
            impl_->nativeReservationHeld = false;
        }
        return false;
    }
#endif
    return impl_->lifecycle.MarkReady();
}

bool DuplexAudioSession::Start(bool headphonesConnected) noexcept
{
    if (!impl_ || impl_->releaseStarted.load(std::memory_order_acquire) ||
        !impl_->lifecycle.Start(impl_->aecSupported, headphonesConnected)) return false;
#ifdef __OHOS__
    const OH_AudioDevice_Type outputDevice =
        SelectCommunicationOutput(headphonesConnected) == CommunicationOutputRoute::Speaker
            ? AUDIO_DEVICE_TYPE_SPEAKER
            : AUDIO_DEVICE_TYPE_DEFAULT;
    (void)OH_AudioRenderer_SetDefaultOutputDevice(impl_->renderer, outputDevice);
    impl_->accompanimentSink.SetRendererActive(true);
    impl_->callbackBridge->Open();
    impl_->diagnosticWriteCallbacks = 0;
    OH_LOG_Print(LOG_APP, LOG_INFO, kAudioDiagDomain, kAudioDiagTag,
        "[PivoMicAudioDiag] start headphones=%{public}d route=%{public}u fastMode=%{public}d "
        "aecSupported=%{public}d",
        headphonesConnected, static_cast<unsigned int>(impl_->mixer.AudioRoute()),
        impl_->fastMode, impl_->aecSupported);
    if (OH_AudioCapturer_Start(impl_->capturer) != AUDIOSTREAM_SUCCESS ||
        OH_AudioRenderer_Start(impl_->renderer) != AUDIOSTREAM_SUCCESS) {
        impl_->HaltAndReset();
        impl_->lifecycle.ApplyHaltOutcome(DuplexControlAction::HaltForError);
        return false;
    }
#else
    impl_->accompanimentSink.SetRendererActive(true);
    impl_->callbackBridge->Open();
#endif
    return true;
}

bool DuplexAudioSession::Pause() noexcept
{
    if (!impl_ || impl_->releaseStarted.load(std::memory_order_acquire) || !impl_->lifecycle.Pause()) return false;
#ifdef __OHOS__
    const bool rendererPaused = OH_AudioRenderer_Pause(impl_->renderer) == AUDIOSTREAM_SUCCESS;
    const bool capturerPaused = OH_AudioCapturer_Pause(impl_->capturer) == AUDIOSTREAM_SUCCESS;
    const DuplexControlAction action = DuplexControlDecision::ResolvePauseResult(capturerPaused, rendererPaused);
    if (action != DuplexControlAction::None) {
        impl_->HaltAndReset();
        impl_->lifecycle.ApplyHaltOutcome(action);
        return false;
    }
    impl_->callbackBridge->Close();
    impl_->DrainCallbacks();
#endif
    impl_->accompanimentSink.SetRendererActive(false);
    return true;
}

bool DuplexAudioSession::Resume() noexcept
{
    if (!impl_ || impl_->releaseStarted.load(std::memory_order_acquire) || !impl_->lifecycle.Resume()) return false;
#ifdef __OHOS__
    impl_->accompanimentSink.SetRendererActive(true);
    impl_->callbackBridge->Open();
    if (OH_AudioCapturer_Start(impl_->capturer) != AUDIOSTREAM_SUCCESS ||
        OH_AudioRenderer_Start(impl_->renderer) != AUDIOSTREAM_SUCCESS) {
        impl_->HaltAndReset();
        impl_->lifecycle.ApplyHaltOutcome(DuplexControlAction::HaltForError);
        return false;
    }
#else
    impl_->accompanimentSink.SetRendererActive(true);
    impl_->callbackBridge->Open();
#endif
    return true;
}

bool DuplexAudioSession::Stop() noexcept
{
    if (!impl_) return true;
    impl_->HaltAndReset();
#ifdef __OHOS__
    const StopResourceOutcome outcome = StopResourceDecision::Resolve(impl_->ReleaseStreams());
    if (outcome == StopResourceOutcome::ErrorRetained) {
        impl_->lifecycle.NotifyError();
        return false;
    }
    if (impl_->nativeReservationHeld && StopResourceDecision::ReleasesReservation(outcome)) {
        ReleaseQuarantine().ReleaseReservation();
        impl_->nativeReservationHeld = false;
    }
    impl_->fastMode = false;
#endif
    return impl_->lifecycle.Stop();
}

void DuplexAudioSession::Poll() noexcept
{
    if (!impl_ || impl_->releaseStarted.load(std::memory_order_acquire)) return;
    const bool error = impl_->callbackError.exchange(false, std::memory_order_acq_rel);
    const bool interrupted = impl_->callbackInterrupted.exchange(false, std::memory_order_acq_rel);
    const AudioInterruptHint hint = impl_->lastInterruptHint.exchange(AudioInterruptHint::None, std::memory_order_acq_rel);
    const DuplexControlAction action = DuplexControlDecision::Resolve(error, interrupted, hint);
    if (action == DuplexControlAction::HaltForError || action == DuplexControlAction::HaltForInterruption) {
        impl_->HaltAndReset();
        impl_->lifecycle.ApplyHaltOutcome(action);
    } else if (action == DuplexControlAction::PauseForInterruption) {
#ifdef __OHOS__
        if (impl_->renderer != nullptr) {
            (void)OH_AudioRenderer_Pause(impl_->renderer);
        }
        if (impl_->capturer != nullptr) {
            (void)OH_AudioCapturer_Pause(impl_->capturer);
        }
#endif
        impl_->accompanimentSink.SetRendererActive(false);
        impl_->lifecycle.ApplyHaltOutcome(action);
    } else if (action == DuplexControlAction::ResumeFromInterruption) {
        impl_->resumeRequested.store(true, std::memory_order_release);
    } else if (action == DuplexControlAction::DuckForInterruption) {
        impl_->isDucked.store(true, std::memory_order_release);
    } else if (action == DuplexControlAction::UnduckForInterruption) {
        impl_->isDucked.store(false, std::memory_order_release);
    }
    if (impl_->callbackDeviceChanged.exchange(false, std::memory_order_acq_rel)) impl_->deviceChanged = true;
}

bool DuplexAudioSession::Release() noexcept
{
    if (!impl_) return true;
    if (impl_->releaseComplete.load(std::memory_order_acquire)) return true;
    impl_->releaseStarted.store(true, std::memory_order_release);
    impl_->HaltAndReset();
#ifdef __OHOS__
    if (!impl_->ReleaseStreams()) {
        impl_->lifecycle.NotifyError();
        return false;
    }
    // OH_Audio{Renderer,Capturer}_Release synchronously relinquish their stream handles;
    // after both return no future callback can be issued for those handles. Drain callbacks
    // that raced the first zero observation while the callback context is still alive.
    impl_->DrainCallbacks();
#endif
    impl_->lifecycle.Stop();
    impl_->releaseComplete.store(true, std::memory_order_release);
#ifdef __OHOS__
    if (impl_->nativeReservationHeld) {
        ReleaseQuarantine().ReleaseReservation();
        impl_->nativeReservationHeld = false;
    }
#endif
    return true;
}

std::size_t DuplexAudioSession::WriteAccompaniment(
    const std::int16_t *stereoSamples, std::size_t sampleCount) noexcept
{
    if (!impl_ || impl_->releaseStarted.load(std::memory_order_acquire) || stereoSamples == nullptr ||
        !DuplexAudioBufferPolicy::IsStereoAligned(sampleCount)) return 0;
    return impl_->accompanimentSink.WriteStereo(stereoSamples, sampleCount);
}

AccompanimentSink& DuplexAudioSession::AccompanimentInput() noexcept { return impl_->accompanimentSink; }

void DuplexAudioSession::SetGains(float accompaniment, float vocal, float reverb) noexcept
{
    if (impl_) impl_->mixer.SetGains(accompaniment, vocal, reverb);
}

void DuplexAudioSession::SetAntiHowlingEnabled(bool enabled) noexcept
{
    if (impl_) impl_->mixer.SetAntiHowlingEnabled(enabled);
}

bool DuplexAudioSession::IsAntiHowlingEnabled() const noexcept
{
    return impl_ ? impl_->mixer.IsAntiHowlingEnabled() : false;
}

void DuplexAudioSession::SetAecEnabled(bool enabled) noexcept
{
    if (impl_) impl_->mixer.SetAecEnabled(enabled);
}

bool DuplexAudioSession::IsAecEnabled() const noexcept
{
    return impl_ ? impl_->mixer.IsAecEnabled() : false;
}

void DuplexAudioSession::SetSpatialReverbEnabled(bool enabled) noexcept
{
    if (impl_) impl_->mixer.SetSpatialReverbEnabled(enabled);
}

bool DuplexAudioSession::IsSpatialReverbEnabled() const noexcept
{
    return impl_ ? impl_->mixer.IsSpatialReverbEnabled() : true;
}

void DuplexAudioSession::SetReverbPreset(uint32_t preset) noexcept
{
    if (impl_) impl_->mixer.SetReverbPreset(static_cast<ReverbPreset>(preset));
}

void DuplexAudioSession::SetParametricEqEnabled(bool enabled) noexcept
{
    if (impl_) impl_->mixer.SetParametricEqEnabled(enabled);
}

bool DuplexAudioSession::IsParametricEqEnabled() const noexcept
{
    return impl_ ? impl_->mixer.IsParametricEqEnabled() : false;
}

void DuplexAudioSession::SetDeEsserEnabled(bool enabled) noexcept
{
    if (impl_) impl_->mixer.SetDeEsserEnabled(enabled);
}

bool DuplexAudioSession::IsDeEsserEnabled() const noexcept
{
    return impl_ ? impl_->mixer.IsDeEsserEnabled() : false;
}

void DuplexAudioSession::SetVocalDynamicsEnabled(bool enabled) noexcept
{
    if (impl_) impl_->mixer.SetVocalDynamicsEnabled(enabled);
}

bool DuplexAudioSession::IsVocalDynamicsEnabled() const noexcept
{
    return impl_ ? impl_->mixer.IsVocalDynamicsEnabled() : false;
}

void DuplexAudioSession::SetAudioRoute(uint32_t route) noexcept
{
    if (impl_) {
        impl_->mixer.SetAudioRoute(static_cast<AudioRouteMode>(route));
#ifdef __OHOS__
        OH_LOG_Print(LOG_APP, LOG_INFO, kAudioDiagDomain, kAudioDiagTag,
            "[PivoMicAudioDiag] routeChanged route=%{public}u", route);
#endif
    }
}

uint32_t DuplexAudioSession::AudioRoute() const noexcept
{
    return impl_ ? static_cast<uint32_t>(impl_->mixer.AudioRoute()) : 0;
}

void DuplexAudioSession::SetAccompanimentPitchShift(float semitones) noexcept
{
    if (impl_) impl_->mixer.SetAccompanimentPitchShift(semitones);
}

float DuplexAudioSession::AccompanimentPitchShift() const noexcept
{
    return impl_ ? impl_->mixer.AccompanimentPitchShift() : 0.0F;
}

void DuplexAudioSession::SetPitchCorrection(bool enabled, float strength, uint32_t scaleType, uint32_t rootNote) noexcept
{
    if (impl_) impl_->mixer.SetPitchCorrection(enabled, strength, scaleType, rootNote);
}

bool DuplexAudioSession::IsPitchCorrectionEnabled() const noexcept
{
    return impl_ ? impl_->mixer.IsPitchCorrectionEnabled() : false;
}

void DuplexAudioSession::StartRecording() noexcept
{
    if (impl_) impl_->mixer.StartRecording();
}

void DuplexAudioSession::StopRecording() noexcept
{
    if (impl_) impl_->mixer.StopRecording();
}

bool DuplexAudioSession::IsRecording() const noexcept
{
    return impl_ ? impl_->mixer.IsRecording() : false;
}

int64_t DuplexAudioSession::RecordedDurationMs() const noexcept
{
    return impl_ ? impl_->mixer.RecordedDurationMs() : 0;
}

bool DuplexAudioSession::ExportRecording(const std::string& outputPath, float vocalGain, float musicGain) const noexcept
{
    return impl_ ? impl_->mixer.ExportRecording(outputPath, vocalGain, musicGain) : false;
}

AccompanimentReferenceRing& DuplexAudioSession::ReferenceRing() noexcept
{
    return impl_->referenceRing;
}

void DuplexAudioSession::ResetOutput() noexcept
{
    if (!impl_) return;
    (void)impl_->accompanimentSink.RequestResetAndWait(std::chrono::milliseconds(0), {});
    impl_->referenceRing.Clear();
    impl_->renderedFrames.store(0, std::memory_order_release);
    impl_->mixer.Reset();
}

DuplexSessionSnapshot DuplexAudioSession::Snapshot() const noexcept
{
    DuplexSessionSnapshot snapshot;
    if (!impl_) return snapshot;
    snapshot.state = impl_->lifecycle.State();
    snapshot.fastMode = impl_->fastMode;
    snapshot.aecSupported = impl_->aecSupported;
    snapshot.interrupted = impl_->callbackInterrupted.load(std::memory_order_acquire) ||
        snapshot.state == SessionState::Interrupted;
    snapshot.resumeRequested = impl_->resumeRequested.exchange(false, std::memory_order_acq_rel);
    snapshot.isDucked = impl_->isDucked.load(std::memory_order_acquire);
    snapshot.error = impl_->callbackError.load(std::memory_order_acquire) || snapshot.state == SessionState::Error;
    snapshot.errorCode = impl_->releaseTracker.Error();
    if (snapshot.error && snapshot.errorCode == EngineError::None) snapshot.errorCode = EngineError::InternalFailure;
    snapshot.deviceChanged = impl_->deviceChanged ||
        impl_->callbackDeviceChanged.load(std::memory_order_acquire);
    snapshot.renderedFrames = impl_->renderedFrames.load(std::memory_order_relaxed);
    snapshot.underruns = impl_->underruns.load(std::memory_order_relaxed);
    snapshot.microphonePeak = impl_->mixer.Peak();
    snapshot.latencyMs = impl_->fastMode ? 20 : 80;
    return snapshot;
}

} // namespace karaoke
