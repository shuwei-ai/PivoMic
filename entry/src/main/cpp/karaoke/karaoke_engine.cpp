#include "karaoke_engine.h"
#include <algorithm>
#include <chrono>
#ifndef PIVOMIC_HOST_TEST
#include "accompaniment_decoder.h"
#endif

namespace karaoke {

ControlExecutor::ControlExecutor():state_(std::make_shared<State>()){auto ready=std::make_shared<std::promise<void>>();auto future=ready->get_future();auto state=state_;thread_=std::thread([state,ready]{state->workerId=std::this_thread::get_id();ready->set_value();Worker(state);});future.get();}
ControlExecutor::~ControlExecutor(){Shutdown();}
void ControlExecutor::Shutdown(){if(!thread_.joinable())return;auto state=state_;{std::lock_guard<std::mutex>l(state->mutex);state->accepting=false;state->stopping=true;}state->wake.notify_one();if(std::this_thread::get_id()==state->workerId)thread_.detach();else thread_.join();}
void ControlExecutor::Worker(std::shared_ptr<State>state){for(;;){std::function<void()>task;{std::unique_lock<std::mutex>l(state->mutex);state->wake.wait(l,[&]{return state->stopping||!state->queue.empty();});if(state->queue.empty()&&state->stopping)break;task=std::move(state->queue.front());state->queue.pop();}task();}}

namespace {
#ifndef PIVOMIC_HOST_TEST
class SessionAdapter final:public KaraokeSessionPort{
public:
    bool Prepare()noexcept override{return v.Prepare();}
    bool Start()noexcept override{return v.Start(safeOutput);}
    bool Pause()noexcept override{return v.Pause();}
    bool Resume()noexcept override{return v.Resume();}
    bool Stop()noexcept override{return v.Stop();}
    void Release()noexcept override{(void)v.Release();}
    void ResetOutput()noexcept override{v.ResetOutput();}
    void SetGains(float a,float b,float c)noexcept override{v.SetGains(a,b,c);}
    void SetSafeOutputConnected(bool value)noexcept override{safeOutput=value;}
    void SetAudioRoute(uint32_t r)noexcept override{v.SetAudioRoute(r);}
    void SetAntiHowlingEnabled(bool e)noexcept override{v.SetAntiHowlingEnabled(e);}
    void SetAecEnabled(bool e)noexcept override{v.SetAecEnabled(e);}
    void SetSpatialReverbEnabled(bool e)noexcept override{v.SetSpatialReverbEnabled(e);}
    void SetReverbPreset(uint32_t p)noexcept override{v.SetReverbPreset(p);}
    void SetParametricEqEnabled(bool e)noexcept override{v.SetParametricEqEnabled(e);}
    void SetDeEsserEnabled(bool e)noexcept override{v.SetDeEsserEnabled(e);}
    void SetVocalDynamicsEnabled(bool e)noexcept override{v.SetVocalDynamicsEnabled(e);}
    void SetAccompanimentPitchShift(float s)noexcept override{v.SetAccompanimentPitchShift(s);}
    void SetPitchCorrection(bool e,float s,uint32_t st,uint32_t rn)noexcept override{v.SetPitchCorrection(e,s,st,rn);}
    void StartRecording()noexcept override{v.StartRecording();}
    void StopRecording()noexcept override{v.StopRecording();}
    bool IsRecording()const noexcept override{return v.IsRecording();}
    int64_t RecordedDurationMs()const noexcept override{return v.RecordedDurationMs();}
    bool ExportRecording(const std::string& p,float vG,float mG)noexcept override{return v.ExportRecording(p,vG,mG);}
    void Poll()noexcept override{v.Poll();}
    DuplexSessionSnapshot Snapshot()const noexcept override{return v.Snapshot();}

    DuplexAudioSession v;
    bool safeOutput{false};
};

class DecoderAdapter final:public KaraokeDecoderPort{
public:
    explicit DecoderAdapter(SessionAdapter&s):v(s.v.AccompanimentInput()){}
    bool Prepare(int f,int64_t o,int64_t z)override{return v.Prepare(f,o,z);}
    bool Start()override{return v.Start();}
    void Pause()noexcept override{v.Pause();}
    bool Seek(int64_t m)override{return v.Seek(m);}
    void Stop()noexcept override{v.Stop();}
    void Release()noexcept override{v.Release();}
    bool IsReady()const noexcept override{auto s=v.GetState();return s==AccompanimentDecoder::State::Running||s==AccompanimentDecoder::State::Ended;}
    bool HasError()const noexcept override{return v.GetState()==AccompanimentDecoder::State::Error;}
    int ErrorCode()const noexcept override{return v.ErrorCode();}
    std::int64_t DurationMs()const noexcept override{return v.DurationMs();}
private:
    AccompanimentDecoder v;
};
#endif
}

#ifndef PIVOMIC_HOST_TEST
KaraokeEngine::KaraokeEngine(){auto s=std::make_unique<SessionAdapter>();auto*raw=s.get();session_=std::move(s);decoder_=std::make_unique<DecoderAdapter>(*raw);}
#endif

KaraokeEngine::KaraokeEngine(std::unique_ptr<KaraokeSessionPort>s,std::unique_ptr<KaraokeDecoderPort>d):session_(std::move(s)),decoder_(std::move(d)){}
KaraokeEngine::~KaraokeEngine()noexcept{try{Release();}catch(...){ }control_.Shutdown();}
float KaraokeEngine::Clamp(float v)noexcept{if(!std::isfinite(v))return 0.F;return std::max(0.F,std::min(2.F,v));}

bool KaraokeEngine::WaitUntilReady(){
    auto end=std::chrono::steady_clock::now()+std::chrono::seconds(2);
    while(!decoder_->IsReady()&&!decoder_->HasError()&&std::chrono::steady_clock::now()<end) {
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    if(!decoder_->IsReady())return false;
    decoder_->Pause();
    ready_=true;
    return true;
}

bool KaraokeEngine::Prepare(int f,int64_t o,int64_t z,int64_t d){
    return control_.Run([this,f,o,z,d]{
        if(released_||f<0||o<0||z<=0||d<0||session_->Snapshot().state!=SessionState::Idle)return false;
        forcedError_=false;
        forcedErrorMessage_.clear();
        auto rollback=[this]{decoder_->Stop();decoder_->Release();(void)session_->Stop();};
        if(!session_->Prepare()){rollback();forcedError_=true;forcedErrorMessage_="audio session prepare failed";return false;}
        if(!decoder_->Prepare(f,o,z)){const int decoderError=decoder_->ErrorCode();rollback();forcedError_=true;forcedErrorMessage_="decoder prepare failed ("+std::to_string(decoderError)+")";return false;}
        durationMs_ = d > 0 ? d : (decoder_->DurationMs() > 0 ? decoder_->DurationMs() : 0);
        basePositionMs_=0;
        ready_=false;
        forcedError_=false;
        forcedErrorMessage_.clear();
        session_->SetGains(accompaniment_,vocal_,reverb_);
        session_->SetAudioRoute(audioRoute_);
        session_->SetAntiHowlingEnabled(antiHowling_);
        session_->SetAecEnabled(aec_);
        session_->SetSpatialReverbEnabled(spatialReverb_);
        session_->SetReverbPreset(reverbPreset_);
        session_->SetParametricEqEnabled(parametricEq_);
        session_->SetDeEsserEnabled(deEsser_);
        session_->SetVocalDynamicsEnabled(vocalDynamics_);
        session_->SetAccompanimentPitchShift(accompanimentPitchShift_);
        session_->SetPitchCorrection(pitchCorrectionEnabled_,pitchCorrectionStrength_,pitchCorrectionScale_,pitchCorrectionRoot_);
        if(!decoder_->Start()){rollback();forcedError_=true;forcedErrorMessage_="decoder start failed";return false;}
        return true;
    });
}

KaraokeEngineSnapshot KaraokeEngine::SnapshotControl(){
    session_->Poll();
    auto s=session_->Snapshot();
    if(!ready_&&(s.state==SessionState::Ready||s.state==SessionState::Paused)&&decoder_->IsReady()){decoder_->Pause();ready_=true;}
    if(durationMs_<=0&&decoder_&&decoder_->DurationMs()>0){durationMs_=decoder_->DurationMs();}
    KaraokeEngineSnapshot o;
    o.state=s.state;
    if((o.state==SessionState::Ready||o.state==SessionState::Paused)&&!ready_)o.state=SessionState::Preparing;
    o.positionMs=RenderedPosition(basePositionMs_,s.renderedFrames,durationMs_);
    o.durationMs=durationMs_;
    o.microphonePeak=s.microphonePeak;
    o.latencyMs=s.latencyMs;
    o.underrunCount=s.underruns;
    o.fastMode=s.fastMode;
    o.aecSupported=s.aecSupported;
    o.audioRoute=audioRoute_;
    o.accompanimentPitchShift=accompanimentPitchShift_;
    o.pitchCorrectionEnabled=pitchCorrectionEnabled_;
    o.pitchCorrectionStrength=pitchCorrectionStrength_;
    o.isRecording=session_->IsRecording();
    o.recordedDurationMs=session_->RecordedDurationMs();
    o.resumeRequested=s.resumeRequested;
    o.isDucked=s.isDucked;
    if(s.interrupted)o.state=SessionState::Interrupted;
    if(s.error){o.state=SessionState::Error;o.errorCode=static_cast<int>(s.errorCode);o.errorMessage="audio session failure";}
    else if(decoder_->HasError()){o.state=SessionState::Error;o.errorCode=decoder_->ErrorCode();o.errorMessage="decoder failure";}
    else if(forcedError_){o.state=SessionState::Error;o.errorCode=static_cast<int>(EngineError::InternalFailure);o.errorMessage=forcedErrorMessage_.empty()?"karaoke lifecycle failure":forcedErrorMessage_;}
    return o;
}

KaraokeEngineSnapshot KaraokeEngine::Snapshot()const{
    return control_.Run([this]{return const_cast<KaraokeEngine*>(this)->SnapshotControl();});
}

bool KaraokeEngine::Start(){
    return control_.Run([this]{
        auto state=SnapshotControl().state;
        if(state==SessionState::Singing)return true;
        if(state==SessionState::Preparing){if(!WaitUntilReady())return false;state=SnapshotControl().state;}
        if(state!=SessionState::Ready&&state!=SessionState::Paused&&state!=SessionState::Interrupted)return false;
        if(state==SessionState::Ready){if(!session_->Start())return false;}
        else if(!session_->Resume())return false;
        if(!decoder_->Start()){(void)session_->Pause();forcedError_=true;return false;}
        return true;
    });
}

bool KaraokeEngine::PauseControl(){
    auto state=SnapshotControl().state;
    if(state==SessionState::Paused||state==SessionState::Interrupted)return true;
    if(state!=SessionState::Singing)return false;
    if(session_->Pause()){decoder_->Pause();return true;}
    decoder_->Pause();(void)session_->Stop();forcedError_=true;return false;
}

bool KaraokeEngine::Pause(){return control_.Run([this]{return PauseControl();});}

bool KaraokeEngine::Seek(int64_t m){
    return control_.Run([this,m]{
        if(released_||m<0)return false;
        auto prior=SnapshotControl().state;
        bool singing=prior==SessionState::Singing;
        if(singing&&!PauseControl())return false;
        decoder_->Pause();
        auto target=std::min(m,durationMs_);
        if(!decoder_->Seek(target)){(void)session_->Stop();forcedError_=true;return false;}
        session_->ResetOutput();
        basePositionMs_=target;
        ready_=false;
        if(!singing)return true;
        if(!WaitUntilReady()||!session_->Resume()||!decoder_->Start()){decoder_->Pause();(void)session_->Stop();forcedError_=true;return false;}
        return true;
    });
}

bool KaraokeEngine::Stop(){
    return control_.Run([this]{
        if(released_)return true;
        auto state=session_->Snapshot().state;
        if(state==SessionState::Idle){durationMs_=0;basePositionMs_=0;forcedError_=false;forcedErrorMessage_.clear();return true;}
        decoder_->Stop();
        bool ok=session_->Stop();
        if(ok){durationMs_=0;basePositionMs_=0;ready_=false;forcedError_=false;forcedErrorMessage_.clear();}
        return ok;
    });
}

void KaraokeEngine::Release(){
    control_.Run([this]{
        if(released_)return;
        decoder_->Stop();(void)session_->Stop();decoder_->Release();session_->Release();
        durationMs_=0;basePositionMs_=0;ready_=false;forcedError_=false;forcedErrorMessage_.clear();
        released_=true;
    });
}

void KaraokeEngine::SetSafeOutputConnected(bool value){
    control_.Run([this,value]{if(released_)throw std::runtime_error("karaoke engine released");session_->SetSafeOutputConnected(value);});
}

void KaraokeEngine::SetAudioRoute(uint32_t route){
    control_.Run([this,route]{audioRoute_=route;session_->SetAudioRoute(route);});
}

void KaraokeEngine::SetAccompanimentGain(float v){
    control_.Run([this,v]{accompaniment_=Clamp(v);session_->SetGains(accompaniment_,vocal_,reverb_);});
}

void KaraokeEngine::SetVocalGain(float v){
    control_.Run([this,v]{vocal_=Clamp(v);session_->SetGains(accompaniment_,vocal_,reverb_);});
}

void KaraokeEngine::SetReverbMix(float v){
    control_.Run([this,v]{reverb_=Clamp(v);session_->SetGains(accompaniment_,vocal_,reverb_);});
}

void KaraokeEngine::SetAntiHowlingEnabled(bool v){
    control_.Run([this,v]{antiHowling_=v;session_->SetAntiHowlingEnabled(v);});
}

void KaraokeEngine::SetAecEnabled(bool v){
    control_.Run([this,v]{aec_=v;session_->SetAecEnabled(v);});
}

void KaraokeEngine::SetSpatialReverbEnabled(bool v){
    control_.Run([this,v]{spatialReverb_=v;session_->SetSpatialReverbEnabled(v);});
}

void KaraokeEngine::SetReverbPreset(uint32_t v){
    control_.Run([this,v]{reverbPreset_=v;session_->SetReverbPreset(v);});
}

void KaraokeEngine::SetParametricEqEnabled(bool v){
    control_.Run([this,v]{parametricEq_=v;session_->SetParametricEqEnabled(v);});
}

void KaraokeEngine::SetDeEsserEnabled(bool v){
    control_.Run([this,v]{deEsser_=v;session_->SetDeEsserEnabled(v);});
}

void KaraokeEngine::SetVocalDynamicsEnabled(bool v){
    control_.Run([this,v]{vocalDynamics_=v;session_->SetVocalDynamicsEnabled(v);});
}

void KaraokeEngine::SetAccompanimentPitchShift(float semitones){
    control_.Run([this,semitones]{
        accompanimentPitchShift_=semitones;
        session_->SetAccompanimentPitchShift(semitones);
    });
}

void KaraokeEngine::SetPitchCorrection(bool enabled, float strength, uint32_t scaleType, uint32_t rootNote){
    control_.Run([this,enabled,strength,scaleType,rootNote]{
        pitchCorrectionEnabled_=enabled;
        pitchCorrectionStrength_=strength;
        pitchCorrectionScale_=scaleType;
        pitchCorrectionRoot_=rootNote;
        session_->SetPitchCorrection(enabled,strength,scaleType,rootNote);
    });
}

void KaraokeEngine::StartRecording(){
    control_.Run([this]{session_->StartRecording();});
}

void KaraokeEngine::StopRecording(){
    control_.Run([this]{session_->StopRecording();});
}

bool KaraokeEngine::ExportRecording(const std::string& outputPath, float vocalGain, float musicGain){
    return control_.Run([this, outputPath, vocalGain, musicGain]{
        return session_->ExportRecording(outputPath, vocalGain, musicGain);
    });
}

} // namespace karaoke
