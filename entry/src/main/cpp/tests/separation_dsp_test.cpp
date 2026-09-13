#include "../separation/spectral_transform.h"
#include <cassert>
#include <cmath>
#include <iostream>
int main() {
  separation::SpectralTransform stft(5120, 1024, 256, 2048);
  std::vector<float> pcm(stft.SampleCount()*2);
  for (size_t i=0;i<pcm.size()/2;i++) {pcm[i*2]=0.2f*std::sin(i*0.031);pcm[i*2+1]=0.1f*std::cos(i*0.053);}
  auto spec=stft.Forward(pcm);
  auto recovered=stft.Inverse(spec.data());
  double error=0;
  for(size_t i=4096;i<pcm.size()-4096;i++) error=std::max(error,static_cast<double>(std::abs(pcm[i]-recovered[i])));
  assert(error<0.001);
  assert(recovered.size()==pcm.size());
  std::cout << "stereo STFT reconstruction error " << error << '\n';
}
