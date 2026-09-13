#include "karaoke/spatial_reverb.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace {

void Check(bool condition, int line)
{
    if (!condition) {
        std::fprintf(stderr, "check failed at line %d\n", line);
        std::abort();
    }
}

} // namespace

#define CHECK(condition) Check((condition), __LINE__)

int main()
{
    karaoke::SpatialReverb reverb(48000);
    reverb.SetRoomSize(0.8F);
    reverb.SetDamping(0.3F);

    // 1. Zero input produces zero output initially
    float outLeft = 1.0F;
    float outRight = 1.0F;
    reverb.ProcessSample(0.0F, outLeft, outRight);
    CHECK(outLeft == 0.0F && outRight == 0.0F);

    // 2. Impulse input creates dense, decaying stereo reverberation tail
    reverb.ProcessSample(1.0F, outLeft, outRight);
    bool hasTailEnergy = false;

    for (int frame = 0; frame < 12000; ++frame) {
        reverb.ProcessSample(0.0F, outLeft, outRight);
        CHECK(std::isfinite(outLeft) && std::isfinite(outRight));
        if (frame > 1000 && (std::fabs(outLeft) > 0.0001F || std::fabs(outRight) > 0.0001F)) {
            hasTailEnergy = true;
        }
    }
    CHECK(hasTailEnergy);

    // 3. Reset clears all internal state
    reverb.Reset();
    reverb.ProcessSample(0.0F, outLeft, outRight);
    CHECK(outLeft == 0.0F && outRight == 0.0F);

    return 0;
}
