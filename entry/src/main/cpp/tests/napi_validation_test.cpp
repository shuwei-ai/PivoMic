#include "karaoke/napi_validation.h"
#include "karaoke/napi_status_policy.h"
#include <cassert>
#include <limits>
using namespace karaoke;
int main(){assert(!ShouldThrowFallback(true,true));assert(ShouldThrowFallback(true,false));assert(ShouldThrowFallback(false,false));assert(ValidatePrepare(3,0,10,100)==ValidationError::None);assert(ValidatePrepare(2147483648.0,0,1,1)==ValidationError::Range);assert(ValidatePrepare(1,9007199254740991.0,1,1)==ValidationError::Range);assert(ValidatePrepare(1,0.5,1,1)==ValidationError::Type);assert(ValidateSeek(2147483648.0)==ValidationError::Range);assert(ValidateGain(std::numeric_limits<double>::infinity())==ValidationError::Type);}
