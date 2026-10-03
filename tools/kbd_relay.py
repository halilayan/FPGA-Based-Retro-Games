#!/usr/bin/env python3
"""
kbd_relay.py -- forwards real key presses/releases to the Basys3 board over
the same UART used for xil_printf, as raw PS/2 Set 2 scan code bytes.

Why this exists: the board's onboard USB HID host (PIC24FJ128) does not
support USB hubs or composite devices, and many wireless-keyboard USB
dongles enumerate that way, so they are never seen on the board's PS/2
lines at all. This script is the workaround: it runs on the PC where the
keyboard already works, and
relays every key event as if it came from a real PS/2 keyboard.

sw/libconsole/kbd.c decodes these bytes identically whether they arrive
this way or from a directly-connected PS/2 keyboard through kbd_axi_if.vhd
- if you remap a key here, update KEY_SCANCODE in kbd.c to match, and
vice versa.

Requires: pyserial, keyboard  ->  pip install pyserial keyboard
On Linux, the `keyboard` library reads raw input devices and needs root:
    sudo python3 tools/kbd_relay.py --port /dev/ttyUSB1

WARNING: while running, this script sees every keystroke on the whole
system (not just one window) - that is how OS-level key hooking works.
Only run it while you are actually testing, on your own machine.

While running, this ALSO prints whatever the board sends back over UART
(xil_printf output), so it doubles as your serial terminal - you do not
need PuTTY/minicom/screen open at the same time on the same port.
"""

import argparse
import sys
import threading
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial not installed - run: pip install pyserial")

try:
    import keyboard
except ImportError:
    sys.exit("keyboard not installed - run: pip install keyboard")

# Must match sw/libconsole/kbd.c's KEY_SCANCODE table exactly.
# name (as the `keyboard` library reports it) -> (extended, scan_code)
KEY_SCANCODE = {
    "up":          (True,  0x75),
    "down":        (True,  0x72),
    "left":        (True,  0x6B),
    "right":       (True,  0x74),
    "z":           (False, 0x1A),  # K_A
    "x":           (False, 0x22),  # K_B
    "enter":       (False, 0x5A),  # K_START
    "right shift": (False, 0x59),  # K_SELECT
    "esc":         (False, 0x76),
    "p":           (False, 0x4D),  # K_PAUSE
}


def should_forward(pressed_keys: set, name: str, pressed: bool) -> bool:
    """True exactly on a real 0->1 transition, or on ANY release, updating
    `pressed_keys` to match. False only for an OS key-repeat ("hold") tick
    of a key already known pressed - see main()'s comment above its own
    pressed_keys for why those must not be forwarded as if they were a
    fresh press.

    A release is ALWAYS forwarded, even one `pressed_keys` didn't expect
    (e.g. this script was (re)started mid-hold, so it never saw the
    matching press) - the whole point of this function is to make a
    stuck-key bit on the board LESS likely, so it must never be the one
    thing swallowing the one message that would have cleared it. kbd.c's
    cur_down &= ~bit is idempotent, so a redundant release is harmless on
    the receiving end anyway.

    Pulled out as its own pure function (no serial I/O) specifically so it
    can be unit-tested directly - see kbd_relay_selftest() below. """
    if pressed:
        if name in pressed_keys:
            return False
        pressed_keys.add(name)
        return True
    else:
        pressed_keys.discard(name)
        return True


def send_key_event(ser: serial.Serial, name: str, pressed: bool) -> None:
    """Real PS/2 Set 2 scan codes: make = [E0]? code, break = [E0]? F0 code
    - exactly ONE E0 prefix either way, never two (kbd.c's kbd_feed_byte()
    only ever needs saw_e0 set once before the F0/code pair; a 2026-10-03
    self-test caught this function previously inserting a second, spec-
    incorrect E0 before an extended key's break code - harmless only
    because kbd.c's E0 handling happens to be idempotent, but still one
    wasted byte on every extended-key release)."""
    entry = KEY_SCANCODE.get(name)
    if entry is None:
        return  # untracked key, ignore (matches kbd.c's own behaviour)
    extended, code = entry

    out = bytearray()
    if extended:
        out.append(0xE0)
    if not pressed:
        out.append(0xF0)
    out.append(code)
    ser.write(bytes(out))


def uart_reader(ser: serial.Serial, stop: threading.Event) -> None:
    """Prints whatever the board sends (xil_printf etc.) so this script
    also serves as a serial monitor while it runs."""
    while not stop.is_set():
        try:
            data = ser.read(256)
        except serial.SerialException:
            break
        if data:
            sys.stdout.write(data.decode("ascii", errors="replace"))
            sys.stdout.flush()


class _FakeSerial:
    """Stand-in for serial.Serial that just records every write() - lets
    send_key_event()/should_forward() be exercised with real byte-level
    assertions, no actual port or board needed."""

    def __init__(self):
        self.sent = bytearray()

    def write(self, data: bytes) -> None:
        self.sent.extend(data)


def kbd_relay_selftest() -> bool:
    """Standalone regression check for should_forward()/send_key_event() -
    run with: python3 tools/kbd_relay.py --selftest (no --port/board/root
    needed). Added 2026-10-03 alongside the repeat-tick dedup fix: this
    logic looked obviously right on a first read (that is exactly how the
    original un-deduplicated version looked too), so it gets the same
    "prove it" treatment as the C-side game fixes today rather than being
    trusted on inspection alone."""
    ok = True

    def check(cond: bool, msg: str) -> None:
        nonlocal ok
        if not cond:
            ok = False
            print(f"FAIL: {msg}", file=sys.stderr)

    # 1) A fresh press forwards and is tracked.
    pressed_keys: set = set()
    check(should_forward(pressed_keys, "down", True) is True,
          "a brand new press was not forwarded")
    check("down" in pressed_keys, "pressed key not added to pressed_keys")

    # 2) OS repeat ticks (same key, still pressed, no release in between)
    #    must NOT be forwarded - this is the actual bug fix.
    for _ in range(5):
        check(should_forward(pressed_keys, "down", True) is False,
              "a repeat tick of an already-held key was forwarded as a fresh press")

    # 3) The release is always forwarded, and clears the tracked state.
    check(should_forward(pressed_keys, "down", False) is True,
          "a real release was not forwarded")
    check("down" not in pressed_keys, "released key not removed from pressed_keys")

    # 4) After a release, the SAME key can be freshly pressed again.
    check(should_forward(pressed_keys, "down", True) is True,
          "a genuine re-press after a release was not forwarded")
    pressed_keys.discard("down")

    # 5) A release of a key never seen as pressed is still forwarded, never
    #    swallowed - see should_forward()'s own docstring for why.
    check(should_forward(set(), "down", False) is True,
          "an unmatched release was swallowed instead of forwarded")

    # 6) Two different keys are tracked independently - holding one must
    #    not affect dedup of the other, and releasing one must not affect
    #    the other's held state (the real Tetris scenario: DOWN held for a
    #    soft drop while also tapping LEFT/RIGHT/rotate).
    pressed_keys = set()
    check(should_forward(pressed_keys, "down", True) is True, "first key press of two not forwarded")
    check(should_forward(pressed_keys, "left", True) is True, "second key's press suppressed by the first key's held state")
    check(should_forward(pressed_keys, "down", True) is False, "key A's repeat forwarded while key B is also held")
    check(should_forward(pressed_keys, "left", False) is True, "key B's release not forwarded")
    check(should_forward(pressed_keys, "down", True) is False, "key A's repeat forwarded after unrelated key B was released")
    check(should_forward(pressed_keys, "down", False) is True, "key A's release not forwarded after key B's own press/release cycle")

    # 7) send_key_event()'s actual byte output is untouched by this change
    #    (dedup happens one layer above it) - a few known-good encodings,
    #    including the single-E0 extended-key break sequence (this is the
    #    exact case the fix above removed a spec-incorrect doubled E0
    #    from).
    fs = _FakeSerial()
    send_key_event(fs, "z", True)
    check(bytes(fs.sent) == bytes([0x1A]), "K_A (z) make code wrong")
    fs = _FakeSerial()
    send_key_event(fs, "z", False)
    check(bytes(fs.sent) == bytes([0xF0, 0x1A]), "K_A (z) break code wrong")
    fs = _FakeSerial()
    send_key_event(fs, "down", True)
    check(bytes(fs.sent) == bytes([0xE0, 0x72]), "extended key (down) make code wrong")
    fs = _FakeSerial()
    send_key_event(fs, "down", False)
    check(bytes(fs.sent) == bytes([0xE0, 0xF0, 0x72]), "extended key (down) break code wrong (must be exactly one E0, not doubled)")
    fs = _FakeSerial()
    send_key_event(fs, "tab", True)
    check(bytes(fs.sent) == bytes(), "an untracked key was forwarded instead of silently ignored")

    if ok:
        print("kbd_relay_selftest: PASS - repeat-tick dedup, cross-key independence, unmatched-release forwarding, and send_key_event encodings verified")
    else:
        print("kbd_relay_selftest: FAIL")
    return ok


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", help="e.g. /dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--selftest", action="store_true",
                     help="run kbd_relay_selftest() and exit - no port/board/root needed")
    args = ap.parse_args()

    if args.selftest:
        return 0 if kbd_relay_selftest() else 1

    if not args.port:
        ap.error("--port is required (unless --selftest)")

    ser = serial.Serial(args.port, args.baud, timeout=0.1)
    print(f"kbd_relay: {args.port} @ {args.baud} baud - Ctrl+C ile cikin")

    stop = threading.Event()
    reader = threading.Thread(target=uart_reader, args=(ser, stop), daemon=True)
    reader.start()

    # See should_forward()'s docstring for why this dedup exists: without
    # it, the OS's own key-repeat mechanism re-sends a tracked key's full
    # make-code bytes 20-40 times a second for as long as it is held - the
    # 2026-10-03 real-hardware root cause behind Tetris's "holding DOWN for
    # a soft drop eventually makes every piece instant-drop" report (lost
    # UART bytes mid scan-code leave that key's bit stuck "down" forever in
    # kbd.c's decoder - see sw/libconsole/port/hw.c's kbd_axi_if_poll()
    # header for the matching symptom on the other keyboard path).
    pressed_keys: set = set()

    def on_event(e: keyboard.KeyboardEvent) -> None:
        pressed = e.event_type == keyboard.KEY_DOWN
        if should_forward(pressed_keys, e.name, pressed):
            send_key_event(ser, e.name, pressed)

    keyboard.hook(on_event)
    try:
        while True:
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        keyboard.unhook_all()
        ser.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
