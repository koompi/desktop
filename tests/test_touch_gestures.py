"""Tests for the touch-gestures state machine.

Run with: python3 tests/test_touch_gestures.py  (or pytest, if installed)
"""

import importlib.util
import pathlib

import evdev
from evdev import ecodes as e

spec = importlib.util.spec_from_loader(
    "touch_gestures",
    importlib.machinery.SourceFileLoader(
        "touch_gestures",
        str(pathlib.Path(__file__).resolve().parent.parent
            / "dots/.local/bin/touch-gestures"),
    ),
)
tg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tg)


class FakeUInput:
    """Records writes and mirrors BTN_TOUCH the way a real uinput node reports it."""

    def __init__(self):
        self.writes = []
        self.touching = False

    def write(self, etype, code, value):
        self.writes.append((etype, code, value))
        if etype == e.EV_KEY and code == e.BTN_TOUCH:
            self.touching = bool(value)

    def write_event(self, event):
        self.write(event.type, event.code, event.value)

    def syn(self):
        pass

    @property
    def device(self):
        return self

    def active_keys(self):
        return [e.BTN_TOUCH] if self.touching else []

    def wheel_total(self):
        return sum(v for t, c, v in self.writes if c == e.REL_WHEEL_HI_RES)


def event(etype, code, value):
    return evdev.InputEvent(0, 0, etype, code, value)


def feed(gesture, clone, events):
    """Drive the gesture the way the daemon does, replaying what it allows."""
    for ev in events:
        if gesture.absorb(ev):
            clone.write_event(ev)
        if ev.type == e.EV_SYN:
            gesture.sync()


def touch_down(y):
    return [
        event(e.EV_ABS, e.ABS_MT_TRACKING_ID, 1),
        event(e.EV_ABS, e.ABS_MT_POSITION_Y, y),
        event(e.EV_KEY, e.BTN_TOUCH, 1),
        event(e.EV_SYN, e.SYN_REPORT, 0),
    ]


def move_to(y):
    return [
        event(e.EV_ABS, e.ABS_MT_POSITION_Y, y),
        event(e.EV_SYN, e.SYN_REPORT, 0),
    ]


def touch_up():
    return [
        event(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1),
        event(e.EV_KEY, e.BTN_TOUCH, 0),
        event(e.EV_SYN, e.SYN_REPORT, 0),
    ]


def drag(start, end, steps=10):
    """A real finger emits a stream of small motions, not one jump."""
    events = []
    for i in range(1, steps + 1):
        events += move_to(start + (end - start) * i // steps)
    return events


def make(units_per_px=1.0):
    clone, wheel = FakeUInput(), FakeUInput()
    gesture = tg.Gesture(clone, wheel, units_per_px)
    gesture.enabled = True
    return gesture, clone, wheel


def test_tap_is_forwarded_untouched():
    gesture, clone, wheel = make()
    feed(gesture, clone, touch_down(500) + move_to(502) + touch_up())

    assert clone.touching is False
    assert wheel.wheel_total() == 0
    assert (e.EV_KEY, e.BTN_TOUCH, 1) in clone.writes


def test_long_drag_lifts_clone_and_scrolls():
    gesture, clone, wheel = make()
    feed(gesture, clone, touch_down(500) + drag(500, 700) + touch_up())

    assert clone.touching is False, "clone must be lifted when scrolling takes over"
    assert wheel.wheel_total() > 0, "dragging down scrolls content down"


def test_drag_up_scrolls_the_other_way():
    gesture, clone, wheel = make()
    feed(gesture, clone, touch_down(500) + drag(500, 300) + touch_up())

    assert wheel.wheel_total() < 0


def test_clone_is_not_forwarded_once_scrolling():
    gesture, clone, wheel = make()
    feed(gesture, clone, touch_down(500) + drag(500, 700))
    before = len(clone.writes)
    feed(gesture, clone, drag(700, 900))

    assert len(clone.writes) == before, "no touch motion may reach the clone mid-scroll"


def test_release_clone_lifts_a_stranded_touch():
    """Regression: a focus change mid-tap used to leave BTN_TOUCH held forever,
    which breaks touch handling for every application, not just wezterm."""
    gesture, clone, _ = make()
    feed(gesture, clone, touch_down(500))
    assert clone.touching is True

    gesture.release_clone()

    assert clone.touching is False
    assert (e.EV_ABS, e.ABS_MT_TRACKING_ID, -1) in clone.writes


def test_fingers_drops_to_zero_after_lift():
    """The daemon gates the grab handover on this, so it must be exact."""
    gesture, clone, _ = make()
    feed(gesture, clone, touch_down(500))
    assert gesture.fingers() == 1

    feed(gesture, clone, touch_up())
    assert gesture.fingers() == 0


def test_disabled_gesture_forwards_nothing():
    gesture, clone, wheel = make()
    gesture.enabled = False
    feed(gesture, clone, touch_down(500) + move_to(600) + touch_up())

    assert clone.writes == []
    assert wheel.wheel_total() == 0


def test_disabled_gesture_still_counts_fingers():
    """Finger tracking must keep working while ungrabbed, or the daemon cannot
    tell when it is safe to take the device over."""
    gesture, clone, _ = make()
    gesture.enabled = False
    feed(gesture, clone, touch_down(500))

    assert gesture.fingers() == 1


if __name__ == "__main__":
    import sys
    import traceback

    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            fn()
            print(f"pass  {name}")
        except AssertionError:
            failures += 1
            print(f"FAIL  {name}")
            traceback.print_exc()
    print(f"\n{failures} failed")
    sys.exit(1 if failures else 0)
