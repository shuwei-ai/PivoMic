#ifndef PIVOMIC_NAPI_STATUS_POLICY_H
#define PIVOMIC_NAPI_STATUS_POLICY_H
namespace karaoke { inline constexpr bool ShouldThrowFallback(bool querySucceeded,bool pending)noexcept{return !querySucceeded||!pending;} }
#endif
