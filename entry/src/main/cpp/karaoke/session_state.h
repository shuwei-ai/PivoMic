#ifndef PIVOMIC_KARAOKE_SESSION_STATE_H
#define PIVOMIC_KARAOKE_SESSION_STATE_H

#include "audio_types.h"

namespace karaoke {

enum class SessionState {
    Idle,
    Preparing,
    Ready,
    Singing,
    Paused,
    Interrupted,
    Error,
};

enum class SessionEvent {
    Prepare,
    Prepared,
    Start,
    Pause,
    Resume,
    Interrupt,
    Reset,
    Fail,
};

struct NativeEngineSnapshot {
    SessionState state {SessionState::Idle};
    EngineError error {EngineError::None};
    AudioFormat format {};
};

class SessionStateMachine {
public:
    [[nodiscard]] SessionState GetState() const noexcept
    {
        return state_;
    }

    [[nodiscard]] bool Transition(SessionEvent event) noexcept
    {
        SessionState nextState = state_;
        switch (state_) {
            case SessionState::Idle:
                if (event == SessionEvent::Prepare) {
                    nextState = SessionState::Preparing;
                }
                break;
            case SessionState::Preparing:
                if (event == SessionEvent::Prepared) {
                    nextState = SessionState::Ready;
                }
                break;
            case SessionState::Ready:
                if (event == SessionEvent::Start) {
                    nextState = SessionState::Singing;
                }
                break;
            case SessionState::Singing:
                if (event == SessionEvent::Pause) {
                    nextState = SessionState::Paused;
                } else if (event == SessionEvent::Interrupt) {
                    nextState = SessionState::Interrupted;
                }
                break;
            case SessionState::Paused:
                if (event == SessionEvent::Resume) {
                    nextState = SessionState::Singing;
                } else if (event == SessionEvent::Interrupt) {
                    nextState = SessionState::Interrupted;
                }
                break;
            case SessionState::Interrupted:
                if (event == SessionEvent::Resume) {
                    nextState = SessionState::Singing;
                } else if (event == SessionEvent::Pause) {
                    nextState = SessionState::Paused;
                } else if (event == SessionEvent::Reset) {
                    nextState = SessionState::Idle;
                }
                break;
            case SessionState::Error:
                if (event == SessionEvent::Reset) {
                    nextState = SessionState::Idle;
                }
                break;
        }

        if (event == SessionEvent::Fail) {
            nextState = SessionState::Error;
        }
        if (nextState == state_) {
            return false;
        }
        state_ = nextState;
        return true;
    }

private:
    SessionState state_ {SessionState::Idle};
};

} // namespace karaoke

#endif // PIVOMIC_KARAOKE_SESSION_STATE_H
