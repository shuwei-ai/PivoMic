#ifndef PIVOMIC_MDX_SEPARATOR_H
#define PIVOMIC_MDX_SEPARATOR_H
#include "spectral_transform.h"
#include "third_party/onnxruntime/onnxruntime_cxx_api.h"
#include <array>
#include <atomic>
#include <cstdio>
#include <functional>
#include <memory>
#include <string>
#include <cstdint>
namespace separation {
using File = std::unique_ptr<FILE, decltype(&fclose)>;
inline File OpenFile(const std::string& path,const char* mode) {
  File f(fopen(path.c_str(),mode),fclose);
  if(!f)throw std::runtime_error("Unable to open audio file");return f;
}
inline void WriteBytes(FILE* f,const void* data,size_t bytes){if(fwrite(data,1,bytes,f)!=bytes)throw std::runtime_error("Unable to write audio: storage full");}
inline void WavHeader(FILE* f,uint32_t frames){
  uint32_t h[11]={0x46464952,frames*4+36,0x45564157,0x20746d66,16,0x00020001,44100,176400,0x00100004,0x61746164,frames*4};
  if(fseek(f,0,SEEK_SET))throw std::runtime_error("Unable to seek output");WriteBytes(f,h,sizeof(h));
}
// Pinned Inst_Main recipe, verified against UVR's original model hash:
// Instrumental, FFT 5120, compensation 1.025. Converted ONNX's FFT metadata is incorrect.
inline void SeparateMdx(const std::string& model,const std::string& raw,const std::string& output,
                        uint64_t frames,std::atomic<bool>& cancel,const std::function<void(float)>& progress) {
  if(!frames || frames>(UINT32_MAX-36)/4)throw std::runtime_error("Audio duration unsupported");
  Ort::Env env(ORT_LOGGING_LEVEL_WARNING,"PivoMicSeparation");
  Ort::SessionOptions options;
  options.SetIntraOpNumThreads(4);options.SetInterOpNumThreads(1);
  options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
  // Arena retention exceeded 1.6 GiB RSS on ADY-AL10 without improving latency.
  options.DisableCpuMemArena();options.DisableMemPattern();
  Ort::Session session(env,model.c_str(),options);
  auto shape=session.GetInputTypeInfo(0).GetTensorTypeAndShapeInfo().GetShape();
  if(shape.size()!=4 || shape[1]!=4 || shape[2]!=2048 || shape[3]!=256)
    throw std::runtime_error("Model dimensions do not match Inst_Main");
  Ort::AllocatorWithDefaultOptions allocator;
  auto inName=session.GetInputNameAllocated(0,allocator),outName=session.GetOutputNameAllocated(0,allocator);
  const char* ins[]={inName.get()};const char* outs[]={outName.get()};
  SpectralTransform transform(5120,1024,256,2048);
  const size_t trim=2560, window=transform.SampleCount(), valid=window-2*trim, stride=valid/2;
  auto source=OpenFile(raw,"rb"), dest=OpenFile(output,"wb");WavHeader(dest.get(),0);
  std::vector<float> accum(valid*2,0),weights(valid,0),pcm(window*2);
  std::vector<int16_t> input(window*2),encoded(stride*2);
  auto memory=Ort::MemoryInfo::CreateCpu(OrtArenaAllocator,OrtMemTypeDefault);
  std::array<int64_t,4> dims{1,4,2048,256};
  for(uint64_t start=0;start<frames;start+=stride){
    if(cancel.load())throw std::runtime_error("cancelled");
    std::fill(pcm.begin(),pcm.end(),0);
    const uint64_t readStart=start>trim?start-trim:0;
    const size_t pad=start<trim?trim-start:0;
    const size_t count=static_cast<size_t>(std::min<uint64_t>(window-pad,frames-readStart));
    if(fseeko(source.get(),static_cast<off_t>(readStart*4),SEEK_SET))throw std::runtime_error("Input seek failed");
    if(fread(input.data(),4,count,source.get())!=count)throw std::runtime_error("Input audio truncated");
    for(size_t i=0;i<count*2;++i)pcm[pad*2+i]=input[i]/32768.0f;
    auto spectrum=transform.Forward(pcm);
    for(size_t plane=0;plane<4;++plane)std::fill_n(spectrum.data()+plane*2048*256,3*256,0.0f);
    auto tensor=Ort::Value::CreateTensor<float>(memory,spectrum.data(),spectrum.size(),dims.data(),dims.size());
    auto result=session.Run(Ort::RunOptions{nullptr},ins,&tensor,1,outs,1);
    if(cancel.load())throw std::runtime_error("cancelled");
    if(result[0].GetTensorTypeAndShapeInfo().GetElementCount()!=spectrum.size())throw std::runtime_error("Invalid model output");
    auto audio=transform.Inverse(result[0].GetTensorData<float>());
    const size_t remaining=static_cast<size_t>(std::min<uint64_t>(valid,frames-start));
    for(size_t i=0;i<remaining;++i){
      float weight=static_cast<float>(0.5-0.5*std::cos(2.0*3.14159265358979323846*(i+0.5)/valid));
      weights[i]+=weight;
      for(size_t c=0;c<2;++c)accum[i*2+c]+=audio[(i+trim)*2+c]*weight*1.025f;
    }
    const size_t emit=std::min(stride,remaining);
    for(size_t i=0;i<emit;++i)for(size_t c=0;c<2;++c){
      float sample=accum[i*2+c]/std::max(1e-8f,weights[i]);
      if(!std::isfinite(sample))throw std::runtime_error("Non-finite model output");
      encoded[i*2+c]=static_cast<int16_t>(std::round(std::clamp(sample,-1.0f,0.999969f)*32768));
    }
    WriteBytes(dest.get(),encoded.data(),emit*4);
    std::move(accum.begin()+stride*2,accum.end(),accum.begin());
    std::fill(accum.end()-stride*2,accum.end(),0);
    std::move(weights.begin()+stride,weights.end(),weights.begin());std::fill(weights.end()-stride,weights.end(),0);
    progress(static_cast<float>(start+emit)/frames);
  }
  if(cancel.load())throw std::runtime_error("cancelled");
  WavHeader(dest.get(),static_cast<uint32_t>(frames));
  if(fflush(dest.get()))throw std::runtime_error("Unable to flush output");
}
}
#endif
