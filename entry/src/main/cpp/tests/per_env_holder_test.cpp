#include "karaoke/per_env_holder.h"
#include <cassert>
struct Value{int state=0;};int main(){karaoke::PerEnvHolder<Value>a,b;a.Get().state=7;b.Get().state=9;a.Reset();assert(a.Get().state==0);assert(b.Get().state==9);}
