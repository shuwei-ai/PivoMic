#ifndef PIVOMIC_SPECTRAL_TRANSFORM_H
#define PIVOMIC_SPECTRAL_TRANSFORM_H
#include <algorithm>
#include <cmath>
#include <complex>
#include <stdexcept>
#include <vector>
namespace separation {
// UVR's centered, periodic-Hann STFT. Planes: L real, L imaginary, R real, R imaginary.
class SpectralTransform {
 public:
  SpectralTransform(size_t fft, size_t hop, size_t frames, size_t bins)
      : n_(fft), hop_(hop), frames_(frames), bins_(bins), window_(fft) {
    if (fft<2 || ((fft & (fft-1)) && (fft%5 || ((fft/5)&(fft/5-1)))) || !hop || frames<2 || bins>fft/2+1)
      throw std::invalid_argument("Unsupported spectral dimensions");
    for(size_t i=0;i<n_;++i) window_[i]=0.5f-0.5f*std::cos(2.0*3.14159265358979323846*i/n_);
  }
  size_t SampleCount() const { return hop_*(frames_-1); }
  std::vector<float> Forward(const std::vector<float>& pcm) const {
    if(pcm.size()!=SampleCount()*2) throw std::invalid_argument("Invalid PCM window");
    std::vector<float> out(4*bins_*frames_);
    std::vector<std::complex<float>> work(n_);
    for(size_t c=0;c<2;++c) for(size_t t=0;t<frames_;++t) {
      for(size_t j=0;j<n_;++j) {
        auto pos=static_cast<int64_t>(t*hop_+j)-static_cast<int64_t>(n_/2);
        if(pos<0)pos=-pos;
        if(pos>=static_cast<int64_t>(SampleCount()))pos=2*static_cast<int64_t>(SampleCount())-pos-2;
        work[j]=pcm[static_cast<size_t>(pos)*2+c]*window_[j];
      }
      Fft(work,false);
      for(size_t f=0;f<bins_;++f) {
        out[((c*2)*bins_+f)*frames_+t]=work[f].real();
        out[((c*2+1)*bins_+f)*frames_+t]=work[f].imag();
      }
    }
    return out;
  }
  std::vector<float> Inverse(const float* spec) const {
    const auto total=SampleCount()+n_;
    std::vector<float> out(SampleCount()*2), weight(total,0), accum(total*2,0);
    std::vector<std::complex<float>> work(n_);
    for(size_t t=0;t<frames_;++t) {
      for(size_t j=0;j<n_;++j) weight[t*hop_+j]+=window_[j]*window_[j];
      for(size_t c=0;c<2;++c) {
        std::fill(work.begin(),work.end(),0);
        for(size_t f=0;f<bins_;++f) work[f]={spec[((c*2)*bins_+f)*frames_+t],spec[((c*2+1)*bins_+f)*frames_+t]};
        for(size_t f=1;f<n_/2;++f)work[n_-f]=std::conj(work[f]);
        Fft(work,true);
        for(size_t j=0;j<n_;++j)accum[(t*hop_+j)*2+c]+=work[j].real()*window_[j];
      }
    }
    for(size_t i=0;i<SampleCount();++i)for(size_t c=0;c<2;++c)
      out[i*2+c]=accum[(i+n_/2)*2+c]/std::max(1e-8f,weight[i+n_/2]);
    return out;
  }
 private:
  static void Fft(std::vector<std::complex<float>>& a,bool inverse) {
    const size_t n=a.size();
    if(n & (n-1)) {
      const size_t m=n/5;
      std::vector<std::complex<float>> part[5];
      for(size_t r=0;r<5;++r){part[r].resize(m);for(size_t j=0;j<m;++j)part[r][j]=a[j*5+r];Fft(part[r],inverse);}
      for(size_t k=0;k<n;++k){
        const double angle=(inverse?2:-2)*3.14159265358979323846*k/n;
        const std::complex<float> step(std::cos(angle),std::sin(angle));
        std::complex<float> sum(0),w(1);
        for(size_t r=0;r<5;++r){sum+=part[r][k%m]*w;w*=step;}
        a[k]=inverse?sum/5.0f:sum;
      }
      return;
    }
    for(size_t i=1,j=0;i<n;++i){size_t bit=n>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j)std::swap(a[i],a[j]);}
    for(size_t len=2;len<=n;len<<=1){
      float angle=static_cast<float>((inverse?2:-2)*3.14159265358979323846/len);
      std::complex<float> step(std::cos(angle),std::sin(angle));
      for(size_t i=0;i<n;i+=len){std::complex<float>w(1);for(size_t j=0;j<len/2;++j){auto u=a[i+j],v=a[i+j+len/2]*w;a[i+j]=u+v;a[i+j+len/2]=u-v;w*=step;}}
    }
    if(inverse)for(auto& v:a)v/=static_cast<float>(n);
  }
  size_t n_,hop_,frames_,bins_;
  std::vector<float> window_;
};
}
#endif
