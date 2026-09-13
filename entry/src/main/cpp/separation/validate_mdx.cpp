#include "mdx_separator.h"
#include <chrono>
#include <iostream>
int main(int argc,char** argv){
  if(argc!=4)return 2;
  auto f=separation::OpenFile(argv[2],"rb");fseeko(f.get(),0,SEEK_END);auto frames=ftello(f.get())/4;f.reset();
  std::atomic<bool>cancel{false};auto start=std::chrono::steady_clock::now();
  try{separation::SeparateMdx(argv[1],argv[2],argv[3],frames,cancel,[](float p){std::cout<<"progress "<<p<<std::endl;});}
  catch(const std::exception& e){std::cerr<<e.what()<<std::endl;return 1;}
  std::cout<<"frames "<<frames<<" seconds "<<std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count()<<std::endl;
}
