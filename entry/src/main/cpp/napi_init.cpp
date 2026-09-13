#include "karaoke/karaoke_engine.h"
#include "karaoke/napi_validation.h"
#include "karaoke/napi_status_policy.h"
#include "karaoke/per_env_holder.h"
#include <napi/native_api.h>
#include <cmath>
#include <exception>

namespace {
using EnvState = karaoke::PerEnvHolder<karaoke::KaraokeEngine>;

EnvState& State(napi_env e)
{
    void *data = nullptr;
    const napi_status status = napi_get_instance_data(e, &data);
    if (status != napi_ok || data == nullptr) {
        throw std::runtime_error("karaoke environment unavailable");
    }
    return *static_cast<EnvState *>(data);
}

karaoke::KaraokeEngine& Engine(napi_env e)
{
    return State(e).Get();
}

bool ThrowError(napi_env e, const char *m)
{
    return napi_throw_error(e, nullptr, m) == napi_ok;
}

bool ThrowTypeError(napi_env e, const char *m)
{
    return napi_throw_type_error(e, nullptr, m) == napi_ok;
}

bool ThrowRangeError(napi_env e, const char *m)
{
    return napi_throw_range_error(e, nullptr, m) == napi_ok;
}

bool Ok(napi_env e, napi_status s)
{
    if (s == napi_ok) return true;
    bool pending = false;
    const napi_status query = napi_is_exception_pending(e, &pending);
    if (karaoke::ShouldThrowFallback(query == napi_ok, pending)) {
        if (!ThrowError(e, "N-API operation failed")) return false;
    }
    return false;
}

napi_value Bad(napi_env e, const char *m)
{
    if (!ThrowTypeError(e, m)) return nullptr;
    return nullptr;
}

napi_value Range(napi_env e, const char *m)
{
    if (!ThrowRangeError(e, m)) return nullptr;
    return nullptr;
}

bool Args(napi_env e, napi_callback_info i, size_t n, napi_value *v)
{
    size_t c = n;
    if (!Ok(e, napi_get_cb_info(e, i, &c, v, nullptr, nullptr))) return false;
    if (c != n) return Bad(e, "invalid argument count") != nullptr;
    for (size_t x = 0; x < c; x++) {
        napi_valuetype t;
        if (!Ok(e, napi_typeof(e, v[x], &t))) return false;
        if (t != napi_number) return Bad(e, "arguments must be numbers") != nullptr;
    }
    return true;
}

bool Num(napi_env e, napi_value v, double &o)
{
    return Ok(e, napi_get_value_double(e, v, &o)) && std::isfinite(o);
}

napi_value Bool(napi_env e, bool v)
{
    napi_value o = nullptr;
    return Ok(e, napi_get_boolean(e, v, &o)) ? o : nullptr;
}

napi_value Undef(napi_env e)
{
    napi_value o = nullptr;
    return Ok(e, napi_get_undefined(e, &o)) ? o : nullptr;
}

napi_value Prepare(napi_env e, napi_callback_info i)
{
    napi_value a[4];
    if (!Args(e, i, 4, a)) return nullptr;
    double f, o, z, d;
    if (!Ok(e, napi_get_value_double(e, a[0], &f)) || !Ok(e, napi_get_value_double(e, a[1], &o)) ||
        !Ok(e, napi_get_value_double(e, a[2], &z)) || !Ok(e, napi_get_value_double(e, a[3], &d))) {
        return nullptr;
    }
    auto x = karaoke::ValidatePrepare(f, o, z, d);
    if (x == karaoke::ValidationError::Type) return Bad(e, "prepare arguments must be finite integers");
    if (x == karaoke::ValidationError::Range) return Range(e, "prepare arguments are out of range");
    return Bool(e, Engine(e).Prepare(static_cast<int>(f), static_cast<int64_t>(o), static_cast<int64_t>(z), static_cast<int64_t>(d)));
}

napi_value Call(napi_env e, napi_callback_info i, bool (karaoke::KaraokeEngine::*f)())
{
    if (!Args(e, i, 0, nullptr)) return nullptr;
    return Bool(e, (Engine(e).*f)());
}

napi_value Start(napi_env e, napi_callback_info i) { return Call(e, i, &karaoke::KaraokeEngine::Start); }
napi_value Pause(napi_env e, napi_callback_info i) { return Call(e, i, &karaoke::KaraokeEngine::Pause); }
napi_value Stop(napi_env e, napi_callback_info i) { return Call(e, i, &karaoke::KaraokeEngine::Stop); }

napi_value Seek(napi_env e, napi_callback_info i)
{
    napi_value a[1];
    if (!Args(e, i, 1, a)) return nullptr;
    double v;
    if (!Ok(e, napi_get_value_double(e, a[0], &v))) return nullptr;
    auto x = karaoke::ValidateSeek(v);
    if (x == karaoke::ValidationError::Type) return Bad(e, "positionMs must be a finite integer");
    if (x == karaoke::ValidationError::Range) return Range(e, "positionMs is out of range");
    return Bool(e, Engine(e).Seek(static_cast<int64_t>(v)));
}

napi_value Release(napi_env e, napi_callback_info i)
{
    if (!Args(e, i, 0, nullptr)) return nullptr;
    auto &state = State(e);
    state.Get().Release();
    state.Reset();
    return Undef(e);
}

napi_value Gain(napi_env e, napi_callback_info i, void (karaoke::KaraokeEngine::*f)(float))
{
    napi_value a[1];
    if (!Args(e, i, 1, a)) return nullptr;
    double v;
    if (!Num(e, a[0], v)) return Bad(e, "gain must be finite");
    (Engine(e).*f)(static_cast<float>(v));
    return Undef(e);
}

napi_value Accompaniment(napi_env e, napi_callback_info i) { return Gain(e, i, &karaoke::KaraokeEngine::SetAccompanimentGain); }
napi_value Vocal(napi_env e, napi_callback_info i) { return Gain(e, i, &karaoke::KaraokeEngine::SetVocalGain); }
napi_value Reverb(napi_env e, napi_callback_info i) { return Gain(e, i, &karaoke::KaraokeEngine::SetReverbMix); }

napi_value BoolSwitch(napi_env e, napi_callback_info i, void (karaoke::KaraokeEngine::*f)(bool))
{
    napi_value a[1];
    size_t c = 1;
    if (!Ok(e, napi_get_cb_info(e, i, &c, a, nullptr, nullptr))) return nullptr;
    if (c != 1) return Bad(e, "invalid argument count");
    napi_valuetype type;
    if (!Ok(e, napi_typeof(e, a[0], &type))) return nullptr;
    if (type != napi_boolean) return Bad(e, "argument must be boolean");
    bool value = false;
    if (!Ok(e, napi_get_value_bool(e, a[0], &value))) return nullptr;
    (Engine(e).*f)(value);
    return Undef(e);
}

napi_value SafeOutput(napi_env e, napi_callback_info i) { return BoolSwitch(e, i, &karaoke::KaraokeEngine::SetSafeOutputConnected); }
napi_value AntiHowling(napi_env e, napi_callback_info i) { return BoolSwitch(e, i, &karaoke::KaraokeEngine::SetAntiHowlingEnabled); }
napi_value Aec(napi_env e, napi_callback_info i) { return BoolSwitch(e, i, &karaoke::KaraokeEngine::SetAecEnabled); }
napi_value SpatialReverb(napi_env e, napi_callback_info i) { return BoolSwitch(e, i, &karaoke::KaraokeEngine::SetSpatialReverbEnabled); }
napi_value ParametricEq(napi_env e, napi_callback_info i) { return BoolSwitch(e, i, &karaoke::KaraokeEngine::SetParametricEqEnabled); }
napi_value DeEsser(napi_env e, napi_callback_info i) { return BoolSwitch(e, i, &karaoke::KaraokeEngine::SetDeEsserEnabled); }
napi_value VocalDynamics(napi_env e, napi_callback_info i) { return BoolSwitch(e, i, &karaoke::KaraokeEngine::SetVocalDynamicsEnabled); }

napi_value AudioRoute(napi_env e, napi_callback_info i)
{
    napi_value a[1];
    if (!Args(e, i, 1, a)) return nullptr;
    double v;
    if (!Num(e, a[0], v) || v < 0 || v > 3) return Bad(e, "audio route must be 0 (Speaker), 1 (SpeakerWithEarReturn), 2 (Bluetooth), or 3 (Wired)");
    Engine(e).SetAudioRoute(static_cast<uint32_t>(v));
    return Undef(e);
}

napi_value ReverbPreset(napi_env e, napi_callback_info i)
{
    napi_value a[1];
    if (!Args(e, i, 1, a)) return nullptr;
    double v;
    if (!Num(e, a[0], v) || v < 0 || v > 3) return Bad(e, "reverb preset must be between 0 and 3");
    Engine(e).SetReverbPreset(static_cast<uint32_t>(v));
    return Undef(e);
}

napi_value PitchShift(napi_env e, napi_callback_info i)
{
    napi_value a[1];
    if (!Args(e, i, 1, a)) return nullptr;
    double v;
    if (!Num(e, a[0], v) || v < -6.0 || v > 6.0) return Bad(e, "pitch shift semitones must be between -6 and +6");
    Engine(e).SetAccompanimentPitchShift(static_cast<float>(v));
    return Undef(e);
}

napi_value PitchCorrection(napi_env e, napi_callback_info i)
{
    napi_value a[4];
    size_t c = 4;
    if (!Ok(e, napi_get_cb_info(e, i, &c, a, nullptr, nullptr))) return nullptr;
    if (c != 4) return Bad(e, "setPitchCorrection requires 4 arguments (enabled, strength, scaleType, rootNote)");
    bool enabled = false;
    if (!Ok(e, napi_get_value_bool(e, a[0], &enabled))) return Bad(e, "enabled must be boolean");
    double strength = 0.0, scaleType = 0.0, rootNote = 0.0;
    if (!Num(e, a[1], strength) || !Num(e, a[2], scaleType) || !Num(e, a[3], rootNote)) {
        return Bad(e, "strength, scaleType, and rootNote must be numbers");
    }
    Engine(e).SetPitchCorrection(enabled, static_cast<float>(strength), static_cast<uint32_t>(scaleType), static_cast<uint32_t>(rootNote));
    return Undef(e);
}

napi_value StartRecording(napi_env e, napi_callback_info i)
{
    if (!Args(e, i, 0, nullptr)) return nullptr;
    Engine(e).StartRecording();
    return Undef(e);
}

napi_value StopRecording(napi_env e, napi_callback_info i)
{
    if (!Args(e, i, 0, nullptr)) return nullptr;
    Engine(e).StopRecording();
    return Undef(e);
}

napi_value ExportRecording(napi_env e, napi_callback_info i)
{
    size_t argc = 1;
    napi_value args[1];
    if (!Ok(e, napi_get_cb_info(e, i, &argc, args, nullptr, nullptr))) return nullptr;
    if (argc < 1) return Bad(e, "outputPath is required");

    size_t strLen = 0;
    if (!Ok(e, napi_get_value_string_utf8(e, args[0], nullptr, 0, &strLen))) return nullptr;
    std::string path(strLen, '\0');
    if (!Ok(e, napi_get_value_string_utf8(e, args[0], path.data(), strLen + 1, &strLen))) return nullptr;

    const bool success = Engine(e).ExportRecording(path);
    return Bool(e, success);
}

const char* State(karaoke::SessionState s)
{
    switch (s) {
        case karaoke::SessionState::Idle: return "Idle";
        case karaoke::SessionState::Preparing: return "Preparing";
        case karaoke::SessionState::Ready: return "Ready";
        case karaoke::SessionState::Singing: return "Singing";
        case karaoke::SessionState::Paused: return "Paused";
        case karaoke::SessionState::Interrupted: return "Interrupted";
        case karaoke::SessionState::Error: return "Error";
    }
    return "Error";
}

bool Str(napi_env e, napi_value o, const char *n, const std::string &v)
{
    napi_value x = nullptr;
    return Ok(e, napi_create_string_utf8(e, v.c_str(), v.size(), &x)) && Ok(e, napi_set_named_property(e, o, n, x));
}

bool Dbl(napi_env e, napi_value o, const char *n, double v)
{
    napi_value x = nullptr;
    return Ok(e, napi_create_double(e, v, &x)) && Ok(e, napi_set_named_property(e, o, n, x));
}

bool Bl(napi_env e, napi_value o, const char *n, bool v)
{
    napi_value x = nullptr;
    return Ok(e, napi_get_boolean(e, v, &x)) && Ok(e, napi_set_named_property(e, o, n, x));
}

napi_value Snapshot(napi_env e, napi_callback_info i)
{
    if (!Args(e, i, 0, nullptr)) return nullptr;
    auto s = Engine(e).Snapshot();
    napi_value o = nullptr;
    if (!Ok(e, napi_create_object(e, &o)) || !Str(e, o, "state", State(s.state)) ||
        !Dbl(e, o, "positionMs", s.positionMs) || !Dbl(e, o, "durationMs", s.durationMs) ||
        !Dbl(e, o, "microphonePeak", s.microphonePeak) || !Dbl(e, o, "latencyMs", s.latencyMs) ||
        !Dbl(e, o, "underrunCount", s.underrunCount) || !Bl(e, o, "fastMode", s.fastMode) ||
        !Bl(e, o, "aecSupported", s.aecSupported) || !Dbl(e, o, "audioRoute", s.audioRoute) ||
        !Dbl(e, o, "accompanimentPitchShift", s.accompanimentPitchShift) ||
        !Bl(e, o, "pitchCorrectionEnabled", s.pitchCorrectionEnabled) ||
        !Dbl(e, o, "pitchCorrectionStrength", s.pitchCorrectionStrength) ||
        !Bl(e, o, "isRecording", s.isRecording) ||
        !Dbl(e, o, "recordedDurationMs", s.recordedDurationMs) ||
        !Bl(e, o, "resumeRequested", s.resumeRequested) ||
        !Bl(e, o, "isDucked", s.isDucked) ||
        !Dbl(e, o, "errorCode", s.errorCode) ||
        !Str(e, o, "errorMessage", s.errorMessage)) {
        return nullptr;
    }
    return o;
}

template<napi_value (*F)(napi_env, napi_callback_info)>
napi_value Guard(napi_env e, napi_callback_info i) noexcept
{
    try {
        return F(e, i);
    } catch (const std::exception &x) {
        if (!ThrowError(e, x.what())) return nullptr;
        return nullptr;
    } catch (...) {
        if (!ThrowError(e, "native karaoke failure")) return nullptr;
        return nullptr;
    }
}

void Finalize(napi_env, void *data, void *) noexcept
{
    delete static_cast<EnvState *>(data);
}

napi_value Init(napi_env e, napi_value exports)
{
    auto state = std::make_unique<EnvState>();
    if (!Ok(e, napi_set_instance_data(e, state.get(), Finalize, nullptr))) return nullptr;
    state.release();
    napi_property_descriptor p[] = {
        {"prepare", nullptr, Guard<Prepare>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"start", nullptr, Guard<Start>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pause", nullptr, Guard<Pause>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"seek", nullptr, Guard<Seek>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Guard<Stop>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, Guard<Release>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSafeOutputConnected", nullptr, Guard<SafeOutput>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setAudioRoute", nullptr, Guard<AudioRoute>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setAccompanimentGain", nullptr, Guard<Accompaniment>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setVocalGain", nullptr, Guard<Vocal>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setReverbMix", nullptr, Guard<Reverb>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setAntiHowlingEnabled", nullptr, Guard<AntiHowling>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setAecEnabled", nullptr, Guard<Aec>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSpatialReverbEnabled", nullptr, Guard<SpatialReverb>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setReverbPreset", nullptr, Guard<ReverbPreset>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setParametricEqEnabled", nullptr, Guard<ParametricEq>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setDeEsserEnabled", nullptr, Guard<DeEsser>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setVocalDynamicsEnabled", nullptr, Guard<VocalDynamics>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setAccompanimentPitchShift", nullptr, Guard<PitchShift>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setPitchCorrection", nullptr, Guard<PitchCorrection>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startRecording", nullptr, Guard<StartRecording>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopRecording", nullptr, Guard<StopRecording>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"exportRecording", nullptr, Guard<ExportRecording>, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getSnapshot", nullptr, Guard<Snapshot>, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    return Ok(e, napi_define_properties(e, exports, sizeof(p) / sizeof(p[0]), p)) ? exports : nullptr;
}

} // namespace

NAPI_MODULE(pivomic_audio, Init)
