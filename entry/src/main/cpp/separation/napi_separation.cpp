#include "mdx_separator.h"
#include "../karaoke/accompaniment_decoder.h"
#include <napi/native_api.h>
#include <thread>
#include <mutex>
#include <unistd.h>
#include <sys/stat.h>
namespace {
struct Job {
  std::atomic<bool> cancel{false},done{false};
  std::mutex mutex;
  std::string phase="preparing",error;
  float progress=0;
  uint64_t frames=0;
  std::thread worker;
  ~Job(){cancel=true;if(worker.joinable())worker.join();}
  void Set(const std::string& p,float v=0){std::lock_guard lock(mutex);phase=p;progress=v;}
};
class DiskSink final : public karaoke::AccompanimentSink {
 public:
  explicit DiskSink(FILE* f):file_(f){}
  std::atomic<bool> failed{false};std::atomic<uint64_t> frames{0};
  size_t Capacity()const noexcept override{return 65536;}
  size_t Writable()const noexcept override{return 65536;}
  size_t WriteStereo(const int16_t* p,size_t count)noexcept override {
    if(failed)return 0;
    if(fwrite(p,sizeof(int16_t),count,file_)!=count){failed=true;return 0;}
    frames+=count/2;return count;
  }
  karaoke::ResetResult RequestResetAndWait(std::chrono::milliseconds,const std::function<bool()>&)override{return karaoke::ResetResult::Completed;}
 private:FILE* file_;
};
struct State { int id=0;std::unique_ptr<Job> job; };
void Run(Job& job,int fd,int64_t offset,int64_t size,std::string model,std::string output){
  const std::string raw=output+".pcm";
  try {
    auto file=separation::OpenFile(raw,"wb");DiskSink sink(file.get());
    karaoke::AccompanimentDecoder decoder(sink,44100);
    if(!decoder.Prepare(fd,offset,size)||!decoder.Start())throw std::runtime_error("Unable to decode song");
    auto last=std::chrono::steady_clock::now();uint64_t previous=0;
    while(decoder.GetState()!=karaoke::AccompanimentDecoder::State::Ended){
      if(job.cancel)throw std::runtime_error("cancelled");
      if(sink.failed)throw std::runtime_error("Not enough storage for decoded audio");
      if(decoder.GetState()==karaoke::AccompanimentDecoder::State::Error)throw std::runtime_error("Audio decoder failed");
      if(sink.frames!=previous){previous=sink.frames;last=std::chrono::steady_clock::now();}
      if(std::chrono::steady_clock::now()-last>std::chrono::seconds(30))throw std::runtime_error("Audio decoder timed out");
      if(sink.frames>(UINT32_MAX-36)/4)throw std::runtime_error("Song too long");
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    decoder.Release();
    if(sink.failed||fflush(file.get()))throw std::runtime_error("Unable to save decoded audio");
    file.reset();
    {std::lock_guard lock(job.mutex);job.frames=sink.frames;}
    job.Set("separating");
    separation::SeparateMdx(model,raw,output,sink.frames,job.cancel,[&](float p){job.Set("separating",p);});
    if(job.cancel)throw std::runtime_error("cancelled");
    job.Set("ready",1);
  }catch(const std::exception& e){
    std::lock_guard lock(job.mutex);job.phase=job.cancel?"cancelled":"failed";job.error=job.cancel?"":e.what();unlink(output.c_str());
  }catch(...){std::lock_guard lock(job.mutex);job.phase="failed";job.error="Unexpected separation failure";unlink(output.c_str());}
  close(fd);unlink(raw.c_str());job.done=true;
}
void Check(napi_status s){if(s!=napi_ok)throw std::runtime_error("Invalid separation argument");}
napi_value Number(napi_env e,double n){napi_value v;Check(napi_create_double(e,n,&v));return v;}
napi_value Text(napi_env e,const std::string& s){napi_value v;Check(napi_create_string_utf8(e,s.c_str(),s.size(),&v));return v;}
std::string String(napi_env e,napi_value v){size_t n=0;Check(napi_get_value_string_utf8(e,v,nullptr,0,&n));if(n>4096)throw std::runtime_error("Path too long");std::string s(n+1,0);Check(napi_get_value_string_utf8(e,v,s.data(),s.size(),&n));s.resize(n);if(s.empty()||s[0]!='/'||s.find('\0')!=std::string::npos)throw std::runtime_error("Expected absolute path");return s;}
int64_t Integer(napi_env e,napi_value v){double n;Check(napi_get_value_double(e,v,&n));if(!std::isfinite(n)||std::floor(n)!=n||std::abs(n)>9007199254740991.0)throw std::runtime_error("Expected safe integer");return static_cast<int64_t>(n);}
struct Args {State* state;size_t count; napi_value values[5]; Args(napi_env e,napi_callback_info info):count(5){void* data=nullptr;Check(napi_get_cb_info(e,info,&count,values,nullptr,&data));state=static_cast<State*>(data);if(!state)throw std::runtime_error("Separation unavailable");}};
template<napi_value(*Fn)(napi_env,Args&)>napi_value Guard(napi_env e,napi_callback_info info){try{Args a(e,info);return Fn(e,a);}catch(const std::exception& ex){napi_throw_error(e,nullptr,ex.what());return nullptr;}catch(...){napi_throw_error(e,nullptr,"Separation operation failed");return nullptr;}}
napi_value Start(napi_env e,Args& a){
  if(a.count!=5)throw std::runtime_error("Expected five arguments");
  if(a.state->job&&!a.state->job->done)throw std::runtime_error("A separation is already running");
  auto fd= Integer(e,a.values[0]),offset=Integer(e,a.values[1]),size=Integer(e,a.values[2]);
  if(fd<0||fd>INT32_MAX||offset<0||size<=0)throw std::runtime_error("Invalid input range");
  struct stat st{};if(fstat(static_cast<int>(fd),&st)||offset>st.st_size||size>st.st_size-offset)throw std::runtime_error("Input range exceeds file");
  auto model=String(e,a.values[3]),output=String(e,a.values[4]);
  int owned=dup(static_cast<int>(fd));if(owned<0)throw std::runtime_error("Cannot retain input file");
  auto job=std::make_unique<Job>();
  try{job->worker=std::thread(Run,std::ref(*job),owned,offset,size,model,output);}catch(...){close(owned);throw;}
  a.state->job=std::move(job);return Number(e,++a.state->id);
}
Job& Get(napi_env e,Args& a){if(a.count!=1||Integer(e,a.values[0])!=a.state->id||!a.state->job)throw std::runtime_error("Unknown separation job");return *a.state->job;}
napi_value Snapshot(napi_env e,Args& a){auto& j=Get(e,a);std::lock_guard lock(j.mutex);napi_value v;Check(napi_create_object(e,&v));Check(napi_set_named_property(e,v,"phase",Text(e,j.phase)));Check(napi_set_named_property(e,v,"progress",Number(e,j.progress)));Check(napi_set_named_property(e,v,"errorMessage",Text(e,j.error)));Check(napi_set_named_property(e,v,"sampleRate",Number(e,44100)));Check(napi_set_named_property(e,v,"frameCount",Number(e,j.frames)));return v;}
napi_value Cancel(napi_env e,Args& a){Get(e,a).cancel=true;return Number(e,0);}
napi_value Release(napi_env e,Args& a){auto& j=Get(e,a);{std::lock_guard lock(j.mutex);if(j.phase!="ready"&&j.phase!="failed"&&j.phase!="cancelled")throw std::runtime_error("Cancel and wait before release");}a.state->job.reset();return Number(e,0);}
void Cleanup(void* data){delete static_cast<State*>(data);}
napi_value Init(napi_env e,napi_value exports){
  auto state=std::make_unique<State>();
  napi_property_descriptor props[]={
    {"startJob",nullptr,Guard<Start>,nullptr,nullptr,nullptr,napi_default,state.get()},
    {"getJobSnapshot",nullptr,Guard<Snapshot>,nullptr,nullptr,nullptr,napi_default,state.get()},
    {"cancelJob",nullptr,Guard<Cancel>,nullptr,nullptr,nullptr,napi_default,state.get()},
    {"releaseJob",nullptr,Guard<Release>,nullptr,nullptr,nullptr,napi_default,state.get()}};
  if(napi_define_properties(e,exports,4,props)!=napi_ok)return nullptr;
  if(napi_add_env_cleanup_hook(e,Cleanup,state.get())!=napi_ok)return nullptr;
  state.release();return exports;
}
}
NAPI_MODULE(pivomic_separation,Init)
