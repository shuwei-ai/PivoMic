#include "karaoke/session_state.h"

#include <cassert>

int main()
{
    karaoke::SessionStateMachine machine;
    assert(machine.GetState() == karaoke::SessionState::Idle);

    assert(machine.Transition(karaoke::SessionEvent::Prepare));
    assert(machine.GetState() == karaoke::SessionState::Preparing);

    assert(!machine.Transition(karaoke::SessionEvent::Start));
    assert(machine.GetState() == karaoke::SessionState::Preparing);

    assert(machine.Transition(karaoke::SessionEvent::Prepared));
    assert(machine.GetState() == karaoke::SessionState::Ready);

    assert(machine.Transition(karaoke::SessionEvent::Start));
    assert(machine.GetState() == karaoke::SessionState::Singing);

    assert(machine.Transition(karaoke::SessionEvent::Interrupt));
    assert(machine.GetState() == karaoke::SessionState::Interrupted);

    assert(machine.Transition(karaoke::SessionEvent::Resume));
    assert(machine.GetState() == karaoke::SessionState::Singing);

    assert(machine.Transition(karaoke::SessionEvent::Interrupt));
    assert(machine.GetState() == karaoke::SessionState::Interrupted);

    assert(machine.Transition(karaoke::SessionEvent::Pause));
    assert(machine.GetState() == karaoke::SessionState::Paused);
}
