#ifndef PIVOMIC_KARAOKE_DUPLEX_AUDIO_SESSION_H
#define PIVOMIC_KARAOKE_DUPLEX_AUDIO_SESSION_H

#include "session_state.h"

#include <cstddef>
#include <cstdint>
#include <atomic>
#include <memory>

namespace karaoke {

enum class CommunicationOutputRoute { SystemDefault, Speaker };

[[nodiscard]] constexpr CommunicationOutputRoute SelectCommunicationOutput(
    bool headphonesConnected) noexcept
{
    return headphonesConnected ? CommunicationOutputRoute::SystemDefault
                               : CommunicationOutputRoute::Speaker;
}
class AccompanimentSink;
class AccompanimentReferenceRing;

class DuplexSafetyPolicy final {
public:
    [[nodiscard]] static constexpr bool CanMonitor(bool /*aecSupported*/, bool /*headphonesConnected*/) noexcept
    {
        return true;
    }
};

class DuplexAudioBufferPolicy final {
public:
    [[nodiscard]] static constexpr bool IsStereoAligned(std::size_t sampleCount) noexcept
    {
        return sampleCount % 2 == 0;
    }
};

class CallbackLifetimeGate final {
public:
    void Open() noexcept;
    void Close() noexcept;
    [[nodiscard]] bool Enter() noexcept;
    void Leave() noexcept;
    void Drain() const noexcept;
    [[nodiscard]] std::uint32_t Active() const noexcept;
    [[nodiscard]] bool IsClosed() const noexcept;

private:
    static constexpr std::uint64_t kClosed = std::uint64_t {1} << 63;
    static constexpr std::uint64_t kActiveMask = kClosed - 1;
    std::atomic<std::uint64_t> state_ {kClosed};
};

class CallbackTargetBridge final {
public:
    void Attach(void *target) noexcept { target_.store(target, std::memory_order_release); }
    void Detach() noexcept { target_.store(nullptr, std::memory_order_release); }
    void Open() noexcept { gate_.Open(); }
    void Close() noexcept { gate_.Close(); }
    [[nodiscard]] bool Enter(void **target) noexcept
    {
        if (target == nullptr) return false;
        if (!gate_.Enter()) {
            *target = nullptr;
            return false;
        }
        *target = target_.load(std::memory_order_acquire);
        return true;
    }
    void Leave() noexcept { gate_.Leave(); }
    void Drain() const noexcept { gate_.Drain(); }

private:
    CallbackLifetimeGate gate_;
    std::atomic<void *> target_ {nullptr};
};

class BoundedReleaseQuarantineState final {
public:
    [[nodiscard]] bool TryReserveForSession() noexcept
    {
        if (reserved_ || rendererLive_ || capturerLive_) return false;
        reserved_ = true;
        return true;
    }
    void ReleaseReservation() noexcept { reserved_ = false; }
    void RetainFailedHandles(bool rendererLive, bool capturerLive) noexcept
    {
        rendererLive_ = rendererLive_ || rendererLive;
        capturerLive_ = capturerLive_ || capturerLive;
        reserved_ = true;
    }
    [[nodiscard]] bool Retry(bool rendererReleased, bool capturerReleased) noexcept
    {
        if (rendererLive_ && rendererReleased) rendererLive_ = false;
        if (capturerLive_ && capturerReleased) capturerLive_ = false;
        if (!rendererLive_ && !capturerLive_) reserved_ = false;
        return !rendererLive_ && !capturerLive_;
    }
    [[nodiscard]] std::size_t EntryCount() const noexcept
    {
        return rendererLive_ || capturerLive_ ? 1 : 0;
    }

private:
    bool reserved_ {false};
    bool rendererLive_ {false};
    bool capturerLive_ {false};
};

class NativeReleaseTracker final {
public:
    void SetLiveHandles(bool rendererLive, bool capturerLive) noexcept
    {
        rendererLive_ = rendererLive;
        capturerLive_ = capturerLive;
        errorVisible_ = false;
    }

    [[nodiscard]] bool ApplyResults(bool rendererReleased, bool capturerReleased) noexcept
    {
        if (rendererLive_ && rendererReleased) rendererLive_ = false;
        if (capturerLive_ && capturerReleased) capturerLive_ = false;
        errorVisible_ = rendererLive_ || capturerLive_;
        return !errorVisible_;
    }

    [[nodiscard]] bool RendererLive() const noexcept { return rendererLive_; }
    [[nodiscard]] bool CapturerLive() const noexcept { return capturerLive_; }
    [[nodiscard]] bool ErrorVisible() const noexcept { return errorVisible_; }
    [[nodiscard]] EngineError Error() const noexcept
    {
        return errorVisible_ ? EngineError::AudioUnavailable : EngineError::None;
    }
    [[nodiscard]] bool CanBuildFallback() const noexcept { return !rendererLive_ && !capturerLive_; }
    [[nodiscard]] bool MustRetainCallbackContext() const noexcept { return !CanBuildFallback(); }

private:
    bool rendererLive_ {false};
    bool capturerLive_ {false};
    bool errorVisible_ {false};
};

enum class AudioInterruptHint {
    None = 0,
    Resume = 1,
    Pause = 2,
    Stop = 3,
    Duck = 4,
    Unduck = 5,
};

enum class DuplexControlAction {
    None,
    PauseForInterruption,
    ResumeFromInterruption,
    DuckForInterruption,
    UnduckForInterruption,
    HaltForInterruption,
    HaltForError,
};

enum class StopResourceOutcome {
    IdleReusable,
    ErrorRetained,
};

class StopResourceDecision final {
public:
    [[nodiscard]] static constexpr StopResourceOutcome Resolve(bool releasesComplete) noexcept
    {
        return releasesComplete ? StopResourceOutcome::IdleReusable : StopResourceOutcome::ErrorRetained;
    }
    [[nodiscard]] static constexpr bool ReleasesReservation(StopResourceOutcome outcome) noexcept
    {
        return outcome == StopResourceOutcome::IdleReusable;
    }
};

class DuplexControlDecision final {
public:
    [[nodiscard]] static constexpr DuplexControlAction Resolve(
        bool error, bool interrupted, AudioInterruptHint hint = AudioInterruptHint::None) noexcept
    {
        if (error) return DuplexControlAction::HaltForError;
        if (!interrupted) return DuplexControlAction::None;
        switch (hint) {
            case AudioInterruptHint::Resume:
                return DuplexControlAction::ResumeFromInterruption;
            case AudioInterruptHint::Duck:
                return DuplexControlAction::DuckForInterruption;
            case AudioInterruptHint::Unduck:
                return DuplexControlAction::UnduckForInterruption;
            case AudioInterruptHint::Pause:
                return DuplexControlAction::PauseForInterruption;
            case AudioInterruptHint::Stop:
                return DuplexControlAction::HaltForInterruption;
            default:
                return DuplexControlAction::HaltForInterruption;
        }
    }

    [[nodiscard]] static constexpr DuplexControlAction ResolvePauseResult(
        bool capturerPaused, bool rendererPaused) noexcept
    {
        return capturerPaused && rendererPaused ? DuplexControlAction::None : DuplexControlAction::HaltForError;
    }
};

class DuplexSessionLifecycle final {
public:
    [[nodiscard]] SessionState State() const noexcept;
    bool Prepare() noexcept;
    bool MarkReady() noexcept;
    bool Start(bool aecSupported, bool headphonesConnected) noexcept;
    bool Pause() noexcept;
    bool Resume() noexcept;
    bool Stop() noexcept;
    void NotifyInterrupted() noexcept;
    void NotifyError() noexcept;
    void ApplyHaltOutcome(DuplexControlAction action) noexcept;

private:
    SessionState state_ {SessionState::Idle};
};

struct DuplexSessionSnapshot {
    SessionState state {SessionState::Idle};
    bool fastMode {false};
    bool aecSupported {false};
    bool interrupted {false};
    bool resumeRequested {false};
    bool isDucked {false};
    bool error {false};
    EngineError errorCode {EngineError::None};
    bool deviceChanged {false};
    std::uint64_t renderedFrames {0};
    std::uint64_t underruns {0};
    float microphonePeak {0};
    std::int64_t latencyMs {0};
};

class DuplexAudioSession final {
public:
    DuplexAudioSession();
    ~DuplexAudioSession();
    DuplexAudioSession(const DuplexAudioSession&) = delete;
    DuplexAudioSession& operator=(const DuplexAudioSession&) = delete;

    bool Prepare() noexcept;
    bool Start(bool headphonesConnected) noexcept;
    bool Pause() noexcept;
    bool Resume() noexcept;
    bool Stop() noexcept;
    void Poll() noexcept;
    [[nodiscard]] bool Release() noexcept;
    std::size_t WriteAccompaniment(const std::int16_t *stereoSamples, std::size_t sampleCount) noexcept;
    [[nodiscard]] AccompanimentSink& AccompanimentInput() noexcept;
    [[nodiscard]] DuplexSessionSnapshot Snapshot() const noexcept;
    void SetGains(float accompaniment, float vocal, float reverb) noexcept;
    void SetAntiHowlingEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsAntiHowlingEnabled() const noexcept;
    void SetAecEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsAecEnabled() const noexcept;
    void SetSpatialReverbEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsSpatialReverbEnabled() const noexcept;
    void SetReverbPreset(uint32_t preset) noexcept;
    void SetParametricEqEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsParametricEqEnabled() const noexcept;
    void SetDeEsserEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsDeEsserEnabled() const noexcept;
    void SetVocalDynamicsEnabled(bool enabled) noexcept;
    [[nodiscard]] bool IsVocalDynamicsEnabled() const noexcept;
    void SetAudioRoute(uint32_t route) noexcept;
    [[nodiscard]] uint32_t AudioRoute() const noexcept;
    void SetAccompanimentPitchShift(float semitones) noexcept;
    [[nodiscard]] float AccompanimentPitchShift() const noexcept;
    void SetPitchCorrection(bool enabled, float strength, uint32_t scaleType, uint32_t rootNote) noexcept;
    [[nodiscard]] bool IsPitchCorrectionEnabled() const noexcept;
    void StartRecording() noexcept;
    void StopRecording() noexcept;
    [[nodiscard]] bool IsRecording() const noexcept;
    [[nodiscard]] int64_t RecordedDurationMs() const noexcept;
    [[nodiscard]] bool ExportRecording(const std::string& outputPath, float vocalGain = 1.2F, float musicGain = 0.8F) const noexcept;
    [[nodiscard]] AccompanimentReferenceRing& ReferenceRing() noexcept;
    void ResetOutput() noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace karaoke

#endif

