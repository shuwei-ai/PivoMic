#ifndef PIVOMIC_NAPI_VALIDATION_H
#define PIVOMIC_NAPI_VALIDATION_H
#include <cmath>
#include <cstdint>
#include <limits>
namespace karaoke {
enum class ValidationError { None, Type, Range };
constexpr double kMaxJsInteger=9007199254740991.0;
inline ValidationError Integer(double v){return !std::isfinite(v)||std::floor(v)!=v?ValidationError::Type:ValidationError::None;}
inline ValidationError ValidatePrepare(double fd,double offset,double size,double duration){if(Integer(fd)!=ValidationError::None||Integer(offset)!=ValidationError::None||Integer(size)!=ValidationError::None||Integer(duration)!=ValidationError::None)return ValidationError::Type;if(fd<0||fd>std::numeric_limits<std::int32_t>::max()||offset<0||size<=0||offset>kMaxJsInteger||size>kMaxJsInteger||offset>kMaxJsInteger-size||duration<0||duration>std::numeric_limits<std::int32_t>::max())return ValidationError::Range;return ValidationError::None;}
inline ValidationError ValidateSeek(double value){if(Integer(value)!=ValidationError::None)return ValidationError::Type;return value<0||value>std::numeric_limits<std::int32_t>::max()?ValidationError::Range:ValidationError::None;}
inline ValidationError ValidateGain(double value){return std::isfinite(value)?ValidationError::None:ValidationError::Type;}
}
#endif
