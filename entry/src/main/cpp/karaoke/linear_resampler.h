#ifndef PIVOMIC_KARAOKE_LINEAR_RESAMPLER_H
#define PIVOMIC_KARAOKE_LINEAR_RESAMPLER_H

#include <algorithm>
#include <cstddef>
#include <cstdint>
namespace karaoke {
class LinearResampler final {
public:
  static constexpr uint32_t kOutputRate = 48000, kOutputChannels = 2;
  explicit LinearResampler(uint32_t outputRate = kOutputRate) : outputRate_(outputRate) {}
  struct Result {
    std::size_t consumedFrames{0}, producedFrames{0};
    bool ok{false};
  };
  Result Process(const int16_t *input, std::size_t frames, uint32_t rate,
                 uint32_t channels, int16_t *output,
                 std::size_t capacity) noexcept {
    if ((frames && !input) || (capacity && !output) || rate == 0 || outputRate_ == 0 ||
        (channels != 1 && channels != 2))
      return {};
    if (configured_ && (rate != rate_ || channels != channels_))
      Reset();
    configured_ = true;
    rate_ = rate;
    channels_ = channels;
    Result result{0, 0, true};
    if (rate == outputRate_) {
      const std::size_t count = std::min(frames, capacity);
      for (std::size_t frame = 0; frame < count; ++frame) {
        const int16_t left = input[frame * channels];
        output[frame * 2] = left;
        output[frame * 2 + 1] = channels == 1 ? left : input[frame * 2 + 1];
      }
      result.consumedFrames = count;
      result.producedFrames = count;
      return result;
    }
    while (result.producedFrames < capacity && pending_)
      Emit(output, result);
    while (result.consumedFrames < frames) {
      const int16_t left = input[result.consumedFrames * channels],
                    right = channels == 1
                                ? left
                                : input[result.consumedFrames * channels + 1];
      ++result.consumedFrames;
      if (!seeded_) {
        previousLeft_ = currentLeft_ = left;
        previousRight_ = currentRight_ = right;
        inputIndex_ = 0;
        pending_ = true;
      } else {
        currentLeft_ = left;
        currentRight_ = right;
        ++inputIndex_;
        pending_ = true;
      }
      while (result.producedFrames < capacity && pending_)
        Emit(output, result);
      if (pending_)
        break;
    }
    return result;
  }
  void Reset() noexcept {
    configured_ = false;
    seeded_ = false;
    pending_ = false;
    inputIndex_ = nextOutput_ = 0;
  }

private:
  void Emit(int16_t *output, Result &result) noexcept {
    const uint64_t boundary = inputIndex_ * outputRate_,
                   position = nextOutput_ * rate_;
    if (position > boundary) {
      pending_ = false;
      previousLeft_ = currentLeft_;
      previousRight_ = currentRight_;
      seeded_ = true;
      return;
    }
    const uint64_t base =
        inputIndex_ == 0 ? 0 : (inputIndex_ - 1) * outputRate_;
    const uint64_t numerator = inputIndex_ == 0 ? 0 : position - base;
    output[result.producedFrames * 2] =
        Lerp(previousLeft_, currentLeft_, numerator, outputRate_);
    output[result.producedFrames * 2 + 1] =
        Lerp(previousRight_, currentRight_, numerator, outputRate_);
    ++result.producedFrames;
    ++nextOutput_;
    if (nextOutput_ * rate_ > boundary) {
      pending_ = false;
      previousLeft_ = currentLeft_;
      previousRight_ = currentRight_;
      seeded_ = true;
    }
  }
  static int16_t Lerp(int16_t a, int16_t b, uint64_t n, uint64_t d) noexcept {
    return static_cast<int16_t>(static_cast<int64_t>(a) +
                                (static_cast<int64_t>(b) - a) *
                                    static_cast<int64_t>(n) /
                                    static_cast<int64_t>(d));
  }
  uint32_t outputRate_;
  uint32_t rate_{0}, channels_{0};
  uint64_t inputIndex_{0}, nextOutput_{0};
  int16_t previousLeft_{0}, previousRight_{0}, currentLeft_{0},
      currentRight_{0};
  bool configured_{false}, seeded_{false}, pending_{false};
};
} // namespace karaoke

#endif
