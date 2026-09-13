#include "karaoke/karaoke_engine.h"

#include <cassert>
#include <cmath>
#include <memory>
#include <thread>
#include <vector>

using namespace karaoke;

namespace {
struct FakeSession final : KaraokeSessionPort {
    int prepares = 0, starts = 0, pauses = 0, resumes = 0, stops = 0, releases = 0;
    float accompaniment = 1, vocal = 1, reverb = 0;
    bool prepareResult=true, startResult=true, pauseResult=true, resumeResult=true; std::vector<std::thread::id> threads;
    bool safeOutput = false;
    DuplexSessionSnapshot snapshot {};
    bool Prepare() noexcept override { ++prepares; if(prepareResult)snapshot.state = SessionState::Ready; return prepareResult; }
    bool Start() noexcept override { threads.push_back(std::this_thread::get_id()); ++starts; if(startResult)snapshot.state = SessionState::Singing; return startResult; }
    bool Pause() noexcept override { threads.push_back(std::this_thread::get_id()); ++pauses; if(pauseResult)snapshot.state = SessionState::Paused; return pauseResult; }
    bool Resume() noexcept override { threads.push_back(std::this_thread::get_id()); ++resumes; if(resumeResult)snapshot.state = SessionState::Singing; return resumeResult; }
    bool Stop() noexcept override { ++stops; snapshot.state = SessionState::Idle; return true; }
    void Release() noexcept override { ++releases; }
    void ResetOutput() noexcept override { snapshot.renderedFrames = 0; }
    void SetGains(float a, float v, float r) noexcept override { accompaniment=a; vocal=v; reverb=r; }
    void SetSafeOutputConnected(bool value) noexcept override { safeOutput = value; }
    DuplexSessionSnapshot Snapshot() const noexcept override { return snapshot; }
    void Poll() noexcept override {}
};
struct FakeDecoder final : KaraokeDecoderPort {
    int prepares=0, starts=0, pauses=0, seeks=0, stops=0, releases=0; bool ready=false, prepareResult=true, startResult=true, seekResult=true;
    bool Prepare(int, int64_t, int64_t) override { ++prepares; return prepareResult; }
    bool Start() override { ++starts; return startResult; }
    void Pause() noexcept override { ++pauses; }
    bool Seek(int64_t) override { ++seeks; return seekResult; }
    void Stop() noexcept override { ++stops; }
    void Release() noexcept override { ++releases; }
    bool IsReady() const noexcept override { return ready; }
    bool HasError() const noexcept override { return false; }
    int ErrorCode() const noexcept override { return 0; }
};
}

int main()
{
    auto session = std::make_unique<FakeSession>(); auto *s = session.get();
    auto decoder = std::make_unique<FakeDecoder>(); auto *d = decoder.get();
    KaraokeEngine engine(std::move(session), std::move(decoder));
    assert(engine.Prepare(3, 0, 99, 120000));
    assert(s->prepares == 1 && d->prepares == 1 && d->starts == 1);
    assert(engine.Snapshot().state == SessionState::Preparing);
    assert(!engine.Start() && s->starts == 0);
    d->ready = true;
    assert(engine.Snapshot().state == SessionState::Ready);
    engine.SetSafeOutputConnected(true); assert(s->safeOutput);
    assert(!engine.Prepare(3, 0, 99, 120000));
    assert(s->prepares == 1 && d->prepares == 1 && d->starts == 1);
    assert(engine.Start() && s->starts == 1 && d->starts == 2);
    s->snapshot.renderedFrames = 48000;
    assert(engine.Snapshot().positionMs == 1000);
    assert(engine.Pause() && s->pauses == 1 && d->pauses == 2);
    assert(engine.Seek(5000) && d->seeks == 1);
    assert(engine.Snapshot().positionMs == 5000);
    s->snapshot.renderedFrames = 48000;
    assert(engine.Snapshot().positionMs == 6000);
    assert(engine.Start() && s->resumes == 1);
    s->snapshot.interrupted = true;
    assert(engine.Snapshot().state == SessionState::Interrupted);
    assert(engine.Start() && s->resumes == 2);
    s->snapshot.interrupted = false;
    assert(engine.Snapshot().state == SessionState::Singing);
    engine.SetAccompanimentGain(-2); engine.SetVocalGain(4); engine.SetReverbMix(.25F);
    assert(s->accompaniment == 0 && s->vocal == 2 && std::fabs(s->reverb-.25F) < .001F);
    assert(engine.Stop());
    engine.Release(); engine.Release();
    assert(s->releases == 1 && d->releases == 1);
    assert(!s->threads.empty() && s->threads[0] != std::this_thread::get_id());
    for (auto id : s->threads) assert(id == s->threads[0]);

    auto failedSession = std::make_unique<FakeSession>(); auto *fs = failedSession.get(); fs->startResult = false;
    auto failedDecoder = std::make_unique<FakeDecoder>(); auto *fd = failedDecoder.get();
    KaraokeEngine failed(std::move(failedSession), std::move(failedDecoder));
    assert(failed.Prepare(4, 0, 8, 1000)); fd->ready = true; (void)failed.Snapshot();
    assert(!failed.Start()); assert(fs->starts == 1 && fd->starts == 1);

    auto pauseSession = std::make_unique<FakeSession>(); auto *ps = pauseSession.get();
    auto pauseDecoder = std::make_unique<FakeDecoder>(); auto *pd = pauseDecoder.get();
    KaraokeEngine pauseFailure(std::move(pauseSession), std::move(pauseDecoder));
    assert(pauseFailure.Prepare(5, 0, 8, 1000)); pd->ready = true; (void)pauseFailure.Snapshot(); assert(pauseFailure.Start());
    ps->pauseResult = false; assert(!pauseFailure.Pause()); assert(pauseFailure.Snapshot().state == SessionState::Error);
    assert(pauseFailure.Stop()); assert(pauseFailure.Snapshot().state == SessionState::Idle);
    assert(pauseFailure.Snapshot().durationMs == 0 && pauseFailure.Snapshot().positionMs == 0);
    assert(RenderedPosition(5000, UINT64_MAX, 120000) == 120000);
    ControlExecutor executor;
    assert(executor.Run([&executor]{ executor.Shutdown(); return 7; }) == 7);
    bool rejected = false;
    try { (void)executor.Run([]{ return 1; }); } catch (const std::runtime_error&) { rejected = true; }
    assert(rejected);

    auto badSession = std::make_unique<FakeSession>(); auto *bs = badSession.get(); bs->prepareResult = false;
    auto untouchedDecoder = std::make_unique<FakeDecoder>(); auto *ud = untouchedDecoder.get();
    KaraokeEngine sessionPrepareFailure(std::move(badSession), std::move(untouchedDecoder));
    assert(!sessionPrepareFailure.Prepare(6, 0, 8, 1000));
    assert(sessionPrepareFailure.Snapshot().state == SessionState::Error);
    assert(sessionPrepareFailure.Snapshot().errorMessage == "audio session prepare failed");
    assert(bs->prepares == 1 && bs->stops == 1 && ud->prepares == 0 && ud->stops == 1 && ud->releases == 1);

    auto preparedSession = std::make_unique<FakeSession>(); auto *prs = preparedSession.get();
    auto badDecoder = std::make_unique<FakeDecoder>(); auto *bd = badDecoder.get(); bd->prepareResult = false;
    KaraokeEngine decoderPrepareFailure(std::move(preparedSession), std::move(badDecoder));
    assert(!decoderPrepareFailure.Prepare(7, 0, 8, 1000));
    assert(decoderPrepareFailure.Snapshot().state == SessionState::Error);
    assert(decoderPrepareFailure.Snapshot().errorMessage == "decoder prepare failed (0)");
    assert(prs->prepares == 1 && prs->stops == 1 && bd->prepares == 1 && bd->stops == 1 && bd->releases == 1);
}
