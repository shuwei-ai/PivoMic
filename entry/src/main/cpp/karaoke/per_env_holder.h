#ifndef PIVOMIC_PER_ENV_HOLDER_H
#define PIVOMIC_PER_ENV_HOLDER_H
#include <memory>
namespace karaoke { template<class T>class PerEnvHolder{public:PerEnvHolder():value_(std::make_unique<T>()){}T&Get(){return *value_;}void Reset(){value_=std::make_unique<T>();}private:std::unique_ptr<T>value_;}; }
#endif
