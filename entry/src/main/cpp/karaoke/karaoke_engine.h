#ifndef PIVOMIC_KARAOKE_ENGINE_H
#define PIVOMIC_KARAOKE_ENGINE_H

#include "audio_route_manager.h"
#include "duplex_audio_session.h"
#include "offline_mastering.h"

#include <algorithm>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <queue>
#include <stdexcept>
#include <string>
#include <thread>
#include <type_traits>

namespace karaoke {

struct KaraokeEngineSnapshot {
    SessionState state {SessionState::Idle};
    std::int64_t positionMs {0};
    std::int64_t durationMs {0};
    float microphonePeak {0.0F};
    std::int64_t latencyMs {0};
    std::uint64_t underrunCount {0};
    bool fastMode {false};
    bool aecSupported {false};
    uint32_t audioRoute {0};
    float accompanimentPitchShift {0.0F};
    bool pitchCorrectionEnabled {false};
    float pitchCorrectionStrength {0.0F};
    bool isRecording {false};
    int64_t recordedDurationMs {0};
    bool resumeRequested {false};
    bool isDucked {false};
    int errorCode {0};
    std::string errorMessage;
};

inline std::int64_t RenderedPosition(std::int64_t base, std::uint64_t frames, std::int64_t duration) noexcept
{
    const std::uint64_t elapsed = frames / 48;
    if (duration <= 0) {
        return base + static_cast<std::int64_t>(elapsed);
    }
    if (duration <= base) return std::max<std::int64_t>(0, duration);
    const std::uint64_t remaining = static_cast<std::uint64_t>(duration - base);
    return elapsed >= remaining ? duration : base + static_cast<std::int64_t>(elapsed);
}

class KaraokeSessionPort {
public:
    virtual ~KaraokeSessionPort() = default;
    virtual bool Prepare() noexcept = 0;
    virtual bool Start() noexcept = 0;
    virtual bool Pause() noexcept = 0;
    virtual bool Resume() noexcept = 0;
    virtual bool Stop() noexcept = 0;
    virtual void Release() noexcept = 0;
    virtual void ResetOutput() noexcept = 0;
    virtual void SetGains(float, float, float) noexcept = 0;
    virtual void SetSafeOutputConnected(bool) noexcept {}
    virtual void SetAudioRoute(uint32_t) noexcept {}
    virtual void SetAntiHowlingEnabled(bool) noexcept {}
    virtual void SetAecEnabled(bool) noexcept {}
    virtual void SetSpatialReverbEnabled(bool) noexcept {}
    virtual void SetReverbPreset(uint32_t) noexcept {}
    virtual void SetParametricEqEnabled(bool) noexcept {}
    virtual void SetDeEsserEnabled(bool) noexcept {}
    virtual void SetVocalDynamicsEnabled(bool) noexcept {}
    virtual void SetAccompanimentPitchShift(float) noexcept {}
    virtual void SetPitchCorrection(bool, float, uint32_t, uint32_t) noexcept {}
    virtual void StartRecording() noexcept {}
    virtual void StopRecording() noexcept {}
    virtual bool IsRecording() const noexcept { return false; }
    virtual int64_t RecordedDurationMs() const noexcept { return 0; }
    virtual bool ExportRecording(const std::string&, float, float) noexcept { return false; }
    virtual void Poll() noexcept = 0;
    virtual DuplexSessionSnapshot Snapshot() const noexcept = 0;
};

class KaraokeDecoderPort {
public:
    virtual ~KaraokeDecoderPort() = default;
    virtual bool Prepare(int, std::int64_t, std::int64_t) = 0;
    virtual bool Start() = 0;
    virtual void Pause() noexcept = 0;
    virtual bool Seek(std::int64_t) = 0;
    virtual void Stop() = 0;
    virtual void Release() = 0;
    virtual bool IsReady() const noexcept = 0;
    virtual bool HasError() const noexcept = 0;
    virtual int ErrorCode() const noexcept = 0;
    virtual std::int64_t DurationMs() const noexcept { return 0; }
};

class ControlExecutor {
    struct State {
        std::mutex mutex;
        std::condition_variable wake;
        std::queue<std::function<void()>> queue;
        std::thread::id workerId {};
        bool accepting {true};
        bool stopping {false};
    };

public:
    ControlExecutor();
    ~ControlExecutor();
    ControlExecutor(const ControlExecutor&) = delete;
    ControlExecutor& operator=(const ControlExecutor&) = delete;

    template<class F>
    auto Run(F f) const -> decltype(f())
    {
        using R = decltype(f());
        auto s = state_;
        if (std::this_thread::get_id() == s->workerId) {
            {
                std::lock_guard<std::mutex> lock(s->mutex);
                if (!s->accepting) throw std::runtime_error("control executor stopped");
            }
            if constexpr (std::is_void_v<R>) {
                f();
                return;
            } else {
                return f();
            }
        }
        auto promise = std::make_shared<std::promise<R>>();
        auto future = promise->get_future();
        {
            std::lock_guard<std::mutex> lock(s->mutex);
            if (!s->accepting) throw std::runtime_error("control executor stopped");
            s->queue.push([f = std::move(f), promise]() mutable {
                try {
                    if constexpr (std::is_void_v<R>) {
                        f();
                        promise->set_value();
                    } else {
                        promise->set_value(f());
                    }
                } catch (...) {
                    promise->set_exception(std::current_exception());
                }
            });
        }
        s->wake.notify_one();
        return future.get();
    }

    void Shutdown();

private:
    static void Worker(std::shared_ptr<State>);
    std::shared_ptr<State> state_;
    std::thread thread_;
};

class KaraokeEngine final {
public:
    KaraokeEngine();
    KaraokeEngine(std::unique_ptr<KaraokeSessionPort>, std::unique_ptr<KaraokeDecoderPort>);
    ~KaraokeEngine() noexcept;

    bool Prepare(int fd, std::int64_t offset, std::int64_t size, std::int64_t durationMs);
    bool Start();
    bool Pause();
    bool Seek(std::int64_t positionMs);
    bool Stop();
    void Release();

    void SetSafeOutputConnected(bool value);
    void SetAudioRoute(uint32_t route);
    void SetAccompanimentGain(float gain);
    void SetVocalGain(float gain);
    void SetReverbMix(float mix);
    void SetAntiHowlingEnabled(bool enabled);
    void SetAecEnabled(bool enabled);
    void SetSpatialReverbEnabled(bool enabled);
    void SetReverbPreset(uint32_t preset);
    void SetParametricEqEnabled(bool enabled);
    void SetDeEsserEnabled(bool enabled);
    void SetVocalDynamicsEnabled(bool enabled);
    void SetAccompanimentPitchShift(float semitones);
    void SetPitchCorrection(bool enabled, float strength, uint32_t scaleType, uint32_t rootNote);
    void StartRecording();
    void StopRecording();
    bool ExportRecording(const std::string& outputPath, float vocalGain = 1.2F, float musicGain = 0.8F);

    KaraokeEngineSnapshot Snapshot() const;

private:
    static float Clamp(float v) noexcept;
    bool PauseControl();
    bool WaitUntilReady();
    KaraokeEngineSnapshot SnapshotControl();

    mutable ControlExecutor control_;
    std::unique_ptr<KaraokeSessionPort> session_;
    std::unique_ptr<KaraokeDecoderPort> decoder_;
    std::int64_t durationMs_ {0};
    std::int64_t basePositionMs_ {0};
    float accompaniment_ {1.0F};
    float vocal_ {1.0F};
    float reverb_ {0.0F};
    uint32_t audioRoute_ {0};
    bool antiHowling_ {true};
    bool aec_ {true};
    bool spatialReverb_ {true};
    bool parametricEq_ {true};
    bool deEsser_ {true};
    bool vocalDynamics_ {true};
    uint32_t reverbPreset_ {0};
    float accompanimentPitchShift_ {0.0F};
    bool pitchCorrectionEnabled_ {false};
    float pitchCorrectionStrength_ {0.0F};
    uint32_t pitchCorrectionScale_ {0};
    uint32_t pitchCorrectionRoot_ {0};
    bool released_ {false};
    bool ready_ {false};
    bool forcedError_ {false};
    std::string forcedErrorMessage_;
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_ENGINE_H
