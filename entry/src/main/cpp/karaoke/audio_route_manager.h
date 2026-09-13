#ifndef PIVOMIC_KARAOKE_AUDIO_ROUTE_MANAGER_H
#define PIVOMIC_KARAOKE_AUDIO_ROUTE_MANAGER_H

#include <cstdint>
#include <string>

namespace karaoke {

/**
 * @brief Represents the active audio routing scenario for mobile karaoke.
 */
enum class AudioRouteMode : uint32_t {
    Speaker = 0,               // 手机外放 (伴奏+实时人声，AEC与防啸叫处理)
    SpeakerWithEarReturn = 1,  // 手机外放+实时耳返 (伴奏外放+人声混响外放，AEC与+4Hz频移防啸叫)
    Bluetooth = 2,             // TWS 蓝牙无线耳机 (伴奏与高清耳返走蓝牙，手机麦拾音)
    Wired = 3                  // 有线耳机 / USB-C DAC (<20ms 超低延时全功能实时耳返)
};

/**
 * @brief Safety and DSP policy evaluator for each audio route.
 */
class AudioRoutePolicy final {
public:
    /**
     * @brief Whether ear-return monitoring to the output stream is allowed.
     * In Speaker mode: Enabled with mandatory AEC and anti-howling processing.
     * In SpeakerWithEarReturn mode: Enabled with AEC and +4Hz frequency shifting.
     * In Bluetooth mode: Disabled (optimized for car & TWS setups to eliminate 150-300ms latency clash, HD music accompaniment only).
     * In Wired mode: Safe and enabled (<20ms roundtrip).
     */
    [[nodiscard]] static constexpr bool IsEarReturnAllowed(AudioRouteMode mode) noexcept
    {
        return mode == AudioRouteMode::Wired ||
            mode == AudioRouteMode::Speaker || mode == AudioRouteMode::SpeakerWithEarReturn;
    }

    /**
     * @brief Whether Acoustic Echo Cancellation (Music AEC) is mandatory.
     */
    [[nodiscard]] static constexpr bool IsAecMandatory(AudioRouteMode mode) noexcept
    {
        return mode == AudioRouteMode::Speaker || mode == AudioRouteMode::SpeakerWithEarReturn;
    }

    /**
     * @brief Whether Anti-Howling (+4Hz Frequency Shift + Notch Filter) is mandatory.
     */
    [[nodiscard]] static constexpr bool IsAntiHowlingMandatory(AudioRouteMode mode) noexcept
    {
        return mode == AudioRouteMode::Speaker || mode == AudioRouteMode::SpeakerWithEarReturn;
    }

    /**
     * @brief Returns human-readable name of the audio route.
     */
    [[nodiscard]] static const char* RouteName(AudioRouteMode mode) noexcept
    {
        switch (mode) {
            case AudioRouteMode::Speaker: return "Speaker (Outer Play With Live Vocal)";
            case AudioRouteMode::SpeakerWithEarReturn: return "Speaker (Outer Play With Live FX Ear-Return)";
            case AudioRouteMode::Bluetooth: return "Bluetooth (Car / TWS HD Music Output)";
            case AudioRouteMode::Wired: return "Wired (Headset / USB DAC)";
        }
        return "Unknown";
    }
};

class AudioRouteManager final {
public:
    explicit AudioRouteManager(AudioRouteMode initialMode = AudioRouteMode::Speaker) noexcept
        : mode_(initialMode) {}

    void SetMode(AudioRouteMode mode) noexcept { mode_ = mode; }
    [[nodiscard]] AudioRouteMode CurrentMode() const noexcept { return mode_; }

    struct RoutePolicyState {
        bool isEarReturnMuted;
        bool isAntiHowlingActive;
        bool isAecRequired;
        bool allowLowLatencyEarReturn;
    };

    [[nodiscard]] RoutePolicyState CurrentPolicy() const noexcept {
        return {
            !AudioRoutePolicy::IsEarReturnAllowed(mode_),
            AudioRoutePolicy::IsAntiHowlingMandatory(mode_),
            AudioRoutePolicy::IsAecMandatory(mode_),
            AudioRoutePolicy::IsEarReturnAllowed(mode_)
        };
    }

private:
    AudioRouteMode mode_ {AudioRouteMode::Speaker};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_AUDIO_ROUTE_MANAGER_H
