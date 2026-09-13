#include "karaoke/duplex_audio_session.h"
#include "karaoke/accompaniment_sink.h"

#include <cassert>
#include <array>
#include <atomic>
#include <thread>

int main()
{
    using karaoke::CommunicationOutputRoute;
    using karaoke::SelectCommunicationOutput;
    assert(SelectCommunicationOutput(false) == CommunicationOutputRoute::Speaker);
    assert(SelectCommunicationOutput(true) == CommunicationOutputRoute::SystemDefault);
    using karaoke::DuplexSafetyPolicy;
    using karaoke::DuplexAudioSession;
    using karaoke::DuplexSessionLifecycle;
    using karaoke::DuplexControlDecision;
    using karaoke::DuplexControlAction;
    using karaoke::CallbackLifetimeGate;
    using karaoke::DuplexAudioBufferPolicy;
    using karaoke::NativeReleaseTracker;
    using karaoke::CallbackTargetBridge;
    using karaoke::BoundedReleaseQuarantineState;
    using karaoke::StopResourceDecision;
    using karaoke::StopResourceOutcome;
    using karaoke::SessionState;

    assert(DuplexSafetyPolicy::CanMonitor(true, false));
    assert(DuplexSafetyPolicy::CanMonitor(false, true));
    assert(DuplexSafetyPolicy::CanMonitor(false, false));
    assert(DuplexSafetyPolicy::CanMonitor(true, true));

    DuplexSessionLifecycle lifecycle;
    assert(!lifecycle.Start(true, false));
    assert(lifecycle.Prepare());
    assert(lifecycle.State() == SessionState::Preparing);
    assert(!lifecycle.Start(true, false));
    assert(lifecycle.MarkReady());
    assert(lifecycle.State() == SessionState::Ready);
    assert(lifecycle.Start(false, false));
    assert(lifecycle.State() == SessionState::Singing);

    assert(lifecycle.Pause());
    assert(lifecycle.State() == SessionState::Paused);
    assert(lifecycle.Resume());
    assert(lifecycle.State() == SessionState::Singing);
    lifecycle.NotifyInterrupted();
    assert(lifecycle.State() == SessionState::Interrupted);
    assert(lifecycle.Resume());
    assert(lifecycle.State() == SessionState::Singing);
    lifecycle.NotifyInterrupted();
    assert(lifecycle.Stop());
    assert(lifecycle.State() == SessionState::Idle);
    assert(lifecycle.Stop());

    assert(lifecycle.Prepare());
    assert(lifecycle.MarkReady());
    assert(lifecycle.Start(false, true));
    lifecycle.NotifyError();
    assert(lifecycle.State() == SessionState::Error);
    assert(!lifecycle.Pause());
    assert(lifecycle.Stop());
    assert(lifecycle.State() == SessionState::Idle);

    DuplexAudioSession session;
    assert(session.Prepare());
    assert(session.Release());
    assert(session.Release());
    assert(session.Snapshot().state == SessionState::Idle);
    assert(!session.Prepare());

    using karaoke::AudioInterruptHint;
    assert(DuplexControlDecision::Resolve(true, true) == DuplexControlAction::HaltForError);
    assert(DuplexControlDecision::Resolve(false, true) == DuplexControlAction::HaltForInterruption);
    assert(DuplexControlDecision::Resolve(false, true, AudioInterruptHint::Pause) == DuplexControlAction::PauseForInterruption);
    assert(DuplexControlDecision::Resolve(false, true, AudioInterruptHint::Resume) == DuplexControlAction::ResumeFromInterruption);
    assert(DuplexControlDecision::Resolve(false, true, AudioInterruptHint::Duck) == DuplexControlAction::DuckForInterruption);
    assert(DuplexControlDecision::Resolve(false, true, AudioInterruptHint::Unduck) == DuplexControlAction::UnduckForInterruption);
    assert(DuplexControlDecision::ResolvePauseResult(false, true) == DuplexControlAction::HaltForError);

    DuplexSessionLifecycle callbackLifecycle;
    assert(callbackLifecycle.Prepare());
    assert(callbackLifecycle.MarkReady());
    assert(callbackLifecycle.Start(true, false));
    callbackLifecycle.ApplyHaltOutcome(DuplexControlDecision::Resolve(true, true));
    assert(callbackLifecycle.State() == SessionState::Error);
    callbackLifecycle.ApplyHaltOutcome(DuplexControlAction::HaltForInterruption);
    assert(callbackLifecycle.State() == SessionState::Error);

    callbackLifecycle.Stop();
    assert(callbackLifecycle.Prepare());
    assert(callbackLifecycle.MarkReady());
    assert(callbackLifecycle.Start(true, false));
    callbackLifecycle.ApplyHaltOutcome(DuplexControlDecision::Resolve(false, true));
    assert(callbackLifecycle.State() == SessionState::Interrupted);

    callbackLifecycle.Stop();
    assert(callbackLifecycle.Prepare());
    assert(callbackLifecycle.MarkReady());
    assert(callbackLifecycle.Start(true, false));
    callbackLifecycle.ApplyHaltOutcome(DuplexControlDecision::ResolvePauseResult(false, true));
    assert(callbackLifecycle.State() == SessionState::Error);

    assert(DuplexAudioBufferPolicy::IsStereoAligned(4));
    assert(!DuplexAudioBufferPolicy::IsStereoAligned(3));
    DuplexAudioSession stereoSession;
    assert(stereoSession.AccompanimentInput().Capacity() >= 4);
    const std::array<std::int16_t, 3> oddStereo {1, 2, 3};
    assert(stereoSession.WriteAccompaniment(oddStereo.data(), oddStereo.size()) == 0);

    CallbackLifetimeGate gate;
    gate.Open();
    std::atomic<bool> run {true};
    std::atomic<std::uint64_t> admitted {0};
    std::thread callbackThread([&] {
        while (run.load(std::memory_order_acquire)) {
            const bool accepted = gate.Enter();
            if (accepted) {
                admitted.fetch_add(1, std::memory_order_relaxed);
                gate.Leave();
            }
        }
    });
    while (admitted.load(std::memory_order_acquire) == 0) std::this_thread::yield();
    gate.Close();
    gate.Drain();
    const std::uint64_t closedCount = admitted.load(std::memory_order_acquire);
    for (int i = 0; i < 10000; ++i) std::this_thread::yield();
    assert(admitted.load(std::memory_order_acquire) == closedCount);
    run.store(false, std::memory_order_release);
    callbackThread.join();
    assert(gate.Active() == 0);
    assert(gate.IsClosed());
    assert(!gate.Enter());

    for (int round = 0; round < 100; ++round) {
        CallbackLifetimeGate raceGate;
        raceGate.Open();
        assert(raceGate.Enter());
        assert(raceGate.Active() == 1);
        std::array<std::thread, 8> racers;
        std::atomic<bool> begin {false};
        for (auto &racer : racers) {
            racer = std::thread([&] {
                while (!begin.load(std::memory_order_acquire)) std::this_thread::yield();
                if (raceGate.Enter()) raceGate.Leave();
            });
        }
        begin.store(true, std::memory_order_release);
        raceGate.Close();
        assert(raceGate.IsClosed());
        assert(!raceGate.Enter());
        raceGate.Leave();
        for (auto &racer : racers) racer.join();
        raceGate.Drain();
        assert(raceGate.Active() == 0);
    }

    NativeReleaseTracker releaseTracker;
    releaseTracker.SetLiveHandles(true, true);
    assert(!releaseTracker.ApplyResults(false, true));
    assert(releaseTracker.RendererLive());
    assert(!releaseTracker.CapturerLive());
    assert(releaseTracker.ErrorVisible());
    assert(releaseTracker.Error() == karaoke::EngineError::AudioUnavailable);
    assert(!releaseTracker.CanBuildFallback());
    assert(releaseTracker.MustRetainCallbackContext());
    assert(releaseTracker.ApplyResults(true, true));
    assert(!releaseTracker.RendererLive());
    assert(!releaseTracker.CapturerLive());
    assert(!releaseTracker.ErrorVisible());
    assert(releaseTracker.Error() == karaoke::EngineError::None);
    assert(releaseTracker.CanBuildFallback());
    assert(!releaseTracker.MustRetainCallbackContext());

    int callbackTarget = 42;
    CallbackTargetBridge bridge;
    bridge.Attach(&callbackTarget);
    bridge.Open();
    void *observedTarget = nullptr;
    assert(bridge.Enter(&observedTarget));
    assert(observedTarget == &callbackTarget);
    bridge.Leave();
    bridge.Close();
    bridge.Drain();
    bridge.Detach();
    observedTarget = &callbackTarget;
    assert(!bridge.Enter(&observedTarget));
    assert(observedTarget == nullptr);

    BoundedReleaseQuarantineState quarantine;
    assert(quarantine.TryReserveForSession());
    assert(!quarantine.TryReserveForSession());
    quarantine.RetainFailedHandles(true, false);
    assert(quarantine.EntryCount() == 1);
    assert(!quarantine.TryReserveForSession());
    quarantine.RetainFailedHandles(true, true);
    assert(quarantine.EntryCount() == 1);
    assert(!quarantine.Retry(false, true));
    assert(!quarantine.TryReserveForSession());
    assert(quarantine.Retry(true, true));
    assert(quarantine.EntryCount() == 0);
    assert(quarantine.TryReserveForSession());
    quarantine.ReleaseReservation();

    assert(StopResourceDecision::Resolve(true) == StopResourceOutcome::IdleReusable);
    assert(StopResourceDecision::Resolve(false) == StopResourceOutcome::ErrorRetained);
    assert(StopResourceDecision::ReleasesReservation(StopResourceOutcome::IdleReusable));
    assert(!StopResourceDecision::ReleasesReservation(StopResourceOutcome::ErrorRetained));

    DuplexAudioSession restartableSession;
    assert(restartableSession.Prepare());
    assert(restartableSession.Start(true));
    assert(restartableSession.Stop());
    assert(restartableSession.Snapshot().state == SessionState::Idle);
    assert(restartableSession.Prepare());
    assert(restartableSession.Start(true));
    assert(restartableSession.Stop());
    assert(restartableSession.Release());
}
