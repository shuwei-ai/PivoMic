#include "karaoke/accompaniment_reference_ring.h"

#include <cstdio>
#include <cstdlib>
#include <vector>

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
    karaoke::AccompanimentReferenceRing ring(1024);
    CHECK(ring.AvailableSamples() == 0);
    CHECK(ring.TotalFramesWritten() == 0);

    const int16_t samples[8] = {100, 200, 300, 400, 500, 600, 700, 800};
    const std::size_t written = ring.WriteReferenceStereo(samples, 8);
    CHECK(written == 8);
    CHECK(ring.TotalFramesWritten() == 4);
    CHECK(ring.AvailableSamples() == 8);

    int16_t readBuf[8] = {};
    const std::size_t read = ring.ReadReferenceStereo(readBuf, 8);
    CHECK(read == 8);
    for (int i = 0; i < 8; ++i) {
        CHECK(readBuf[i] == samples[i]);
    }
    CHECK(ring.AvailableSamples() == 0);

    // Nullptr and zero safety
    CHECK(ring.WriteReferenceStereo(nullptr, 0) == 0);
    CHECK(ring.ReadReferenceStereo(nullptr, 0) == 0);

    // Clear
    ring.WriteReferenceStereo(samples, 8);
    CHECK(ring.AvailableSamples() == 8);
    ring.Clear();
    CHECK(ring.AvailableSamples() == 0);
    CHECK(ring.TotalFramesWritten() == 0);

    return 0;
}
