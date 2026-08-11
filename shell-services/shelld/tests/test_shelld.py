#!/usr/bin/env python3
"""Conformance suite for the koompi-shelld NDJSON protocol.

PROTOCOL.md, not the Rust, is the contract, the way tests/test_daemon.py holds the two
global menu daemons to theirs and tests/test_audiod.py holds audiod to its own. SHELLD
points this at the binary under test.

It runs against the live system bus, because a fake that answers the daemon's own
assumptions proves nothing about NetworkManager or UPower. It is read-only against the
seat by construction:

  - it never enables or disables the radio, never scans, never connects and never
    disconnects,
  - the one write it makes is the charge threshold set to the value the daemon has just
    reported for it, so the write path is exercised and the pack is left as it was,
  - `connect` is only ever sent to an object path that cannot exist, to prove the
    refusal, and is refused before NetworkManager is asked anything. The same holds for
    the bluetooth device commands,
  - it never moves a panel and never powers a radio: `set_brightness` is only sent to a
    panel id no backend answers to.

Run: SHELLD=./target/debug/koompi-shelld python3 shelld/tests/test_shelld.py
"""

import json
import os
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SHELLD = os.environ.get(
    "SHELLD", os.path.join(HERE, "..", "..", "target", "debug", "koompi-shelld")
)

failures = []


def check(condition, message):
    if condition:
        print("  ok   %s" % message)
    else:
        print("  FAIL %s" % message)
        failures.append(message)


class Daemon:
    """One koompi-shelld, with every line it has written so far."""

    def __init__(self, **env):
        self.lines = []
        self.lock = threading.Lock()
        self.proc = subprocess.Popen(
            [SHELLD],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
            env={**os.environ, **env},
        )
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        for line in self.proc.stdout:
            line = line.strip()
            if not line:
                continue
            with self.lock:
                self.lines.append(json.loads(line))

    def send(self, **message):
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()

    def seen(self):
        with self.lock:
            return list(self.lines)

    def wait_for(self, predicate, timeout=15.0):
        """The first message matching, or None. Returns the whole log's index too."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            for index, message in enumerate(self.seen()):
                if predicate(message):
                    return index, message
            time.sleep(0.05)
        return None, None

    def reply_to(self, request_id, timeout=15.0):
        return self.wait_for(
            lambda m: m.get("type") == "reply" and m.get("id") == request_id, timeout
        )[1]

    def close(self):
        try:
            self.proc.stdin.close()
        except (BrokenPipeError, ValueError):
            pass
        try:
            return self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            return None


def is_state(service):
    return lambda m: m.get("type") == "state" and m.get("service") == service


def is_start(service):
    """A state or an unavailable: both are a legitimate answer to a subscribe."""
    return lambda m: m.get("service") == service and m.get("type") in (
        "state",
        "unavailable",
    )


def test_hello_is_first_and_nothing_follows_it_unasked():
    daemon = Daemon()
    _, hello = daemon.wait_for(lambda m: m.get("type") == "hello", timeout=10)
    check(hello is not None, "hello is emitted")
    if hello:
        check(daemon.seen()[0] is hello, "hello is the first line")
        check(hello.get("protocol") == 1, "protocol is 1")
        check(hello.get("daemon") == "koompi-shelld", "daemon names itself")
        check(
            set(hello.get("services", [])) >= {"hyprland", "network", "power", "brightness", "bluetooth"},
            "hello advertises hyprland, network and power",
        )

    time.sleep(2.0)
    check(
        len(daemon.seen()) == 1,
        "nothing is emitted before a subscribe (saw %d lines)" % len(daemon.seen()),
    )

    daemon.send(cmd="ping", id=1)
    check(daemon.reply_to(1, timeout=5) is not None, "ping is answered")
    check(
        len([m for m in daemon.seen() if m.get("type") == "state"]) == 0,
        "a ping still starts no service",
    )
    daemon.close()


def test_subscribe_emits_state_before_its_reply():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=10, services=["network", "power"])

    reply = daemon.reply_to(10, timeout=25)
    check(reply is not None and reply.get("ok") is True, "subscribe is accepted")

    log = daemon.seen()
    reply_at = next(
        i for i, m in enumerate(log) if m.get("type") == "reply" and m.get("id") == 10
    )
    for service in ("network", "power"):
        starts = [
            i for i, m in enumerate(log[:reply_at]) if is_start(service)(log[i])
        ]
        check(
            len(starts) >= 1,
            "%s answered the subscribe before the reply landed" % service,
        )

    for service in ("network", "power"):
        _, first = daemon.wait_for(is_state(service), timeout=1)
        if first is not None:
            check(first.get("serial") == 1, "%s serial starts at 1" % service)
    daemon.close()


def test_subscribing_twice_re_emits_rather_than_going_quiet():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=15, services=["power"])
    check(daemon.reply_to(15, timeout=25) is not None, "power subscribed")

    before = len(daemon.seen())
    daemon.send(cmd="subscribe", id=16, services=["power"])
    reply = daemon.reply_to(16, timeout=15)
    check(reply is not None and reply.get("ok") is True, "the second subscribe is accepted")

    tail = daemon.seen()[before:]
    states = [i for i, m in enumerate(tail) if is_start("power")(m)]
    replies = [i for i, m in enumerate(tail) if m.get("id") == 16]
    check(len(states) >= 1, "subscribing again re-emits the state")
    if states and replies:
        check(states[0] < replies[0], "the re-emitted state still precedes the reply")
    daemon.close()


def test_get_state_re_emits_before_replying_and_serial_advances():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=20, services=["power"])
    check(daemon.reply_to(20, timeout=25) is not None, "power subscribed")

    before = len(daemon.seen())
    daemon.send(cmd="get_state", id=21, service="power")
    reply = daemon.reply_to(21, timeout=10)
    check(reply is not None and reply.get("ok") is True, "get_state is accepted")

    after = daemon.seen()
    tail = after[before:]
    states = [m for m in tail if is_state("power")(m)]
    replies = [i for i, m in enumerate(tail) if m.get("id") == 21]
    check(len(states) >= 1, "get_state produced a state")
    if states and replies:
        state_at = next(i for i, m in enumerate(tail) if is_state("power")(m))
        check(state_at < replies[0], "the state comes before the reply")
        check(states[0]["serial"] > 1, "serial advanced past the subscribe's snapshot")
    daemon.close()


def test_the_error_codes_are_the_ones_the_document_names():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=30, services=["power"])
    daemon.reply_to(30, timeout=25)

    cases = [
        (31, dict(cmd="get_state", service="teapot"), "unknown_service"),
        (32, dict(cmd="request_scan", service="network"), "not_subscribed"),
        (33, dict(cmd="nonsense", service="power"), "unknown_command"),
        (34, dict(cmd="set_profile", service="power"), "bad_request"),
        (
            35,
            dict(cmd="set_charge_threshold_enabled", service="power", enabled="yes"),
            "bad_request",
        ),
    ]
    for request_id, message, want in cases:
        daemon.send(id=request_id, **message)
        reply = daemon.reply_to(request_id, timeout=10)
        got = reply.get("error") if reply else None
        check(got == want, "%s answers %s (got %s)" % (message["cmd"], want, got))

    daemon.proc.stdin.write("this is not json\n")
    daemon.proc.stdin.write("\n")
    daemon.proc.stdin.flush()
    _, malformed = daemon.wait_for(
        lambda m: m.get("type") == "reply" and m.get("error") == "malformed", timeout=10
    )
    check(malformed is not None, "an unreadable line answers malformed")
    check(
        len(
            [
                m
                for m in daemon.seen()
                if m.get("type") == "reply" and m.get("error") == "malformed"
            ]
        )
        == 1,
        "a blank line draws no reply",
    )
    daemon.close()


def test_an_access_point_that_is_not_in_the_snapshot_is_refused():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=40, services=["network"])
    daemon.reply_to(40, timeout=25)

    _, state = daemon.wait_for(is_state("network"), timeout=5)
    if state is None:
        print("  skip no network state; NetworkManager did not answer")
        daemon.close()
        return

    daemon.send(
        cmd="connect",
        id=41,
        service="network",
        path="/org/freedesktop/NetworkManager/AccessPoint/nonexistent",
    )
    reply = daemon.reply_to(41, timeout=10)
    check(
        reply is not None and reply.get("error") == "unknown_access_point",
        "a stale access point path is refused, not connected to",
    )
    daemon.close()


def test_the_network_state_carries_what_the_qml_binds_to():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=50, services=["network"])
    daemon.reply_to(50, timeout=25)
    _, message = daemon.wait_for(is_state("network"), timeout=5)
    if message is None:
        print("  skip no network state; NetworkManager did not answer")
        daemon.close()
        return

    state = message["state"]
    for field in (
        "ethernet",
        "connected",
        "network_name",
        "network_strength",
        "captive_portal",
        "connectivity",
    ):
        check(field in state, "network state carries %s" % field)

    wifi = state["wifi"]
    check(
        state["connected"]
        == (state["ethernet"] or (wifi["enabled"] and wifi["status"] == "connected")),
        "connected agrees with Network.qml:37's definition",
    )
    check(
        state["captive_portal"] == (state["connectivity"] == "portal"),
        "captive_portal agrees with connectivity",
    )

    for ap in wifi["networks"]:
        if not ap["ssid_valid_utf8"]:
            continue
        check(
            bytes.fromhex(ap["ssid_hex"]).decode("utf-8") == ap["ssid"],
            "ssid_hex decodes to ssid for %r" % ap["ssid"],
        )
        break
    else:
        if wifi["networks"]:
            print("  skip every ssid in range is non-utf8")

    check(
        len(wifi["networks_by_ssid"]) <= len(wifi["networks"]),
        "the deduped view is no larger than the per-bssid one",
    )
    hexes = [ap["ssid_hex"] for ap in wifi["networks_by_ssid"]]
    check(len(hexes) == len(set(hexes)), "networks_by_ssid holds one row per ssid")
    daemon.close()


def test_the_charge_threshold_write_path_answers_without_moving_the_pack():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=60, services=["power"])
    daemon.reply_to(60, timeout=25)
    _, message = daemon.wait_for(is_state("power"), timeout=5)
    if message is None:
        print("  skip no power state; UPower did not answer")
        daemon.close()
        return

    primary = message["state"].get("primary")
    if not primary:
        print("  skip this seat has no battery")
        daemon.close()
        return

    threshold = primary["threshold"]
    for field in ("supported", "enabled", "start", "end"):
        check(field in threshold, "the threshold carries %s" % field)

    if not threshold["supported"]:
        print("  skip this pack has no charge threshold to write")
        daemon.close()
        return

    # the value it already holds: the write is proven, the pack is not touched
    daemon.send(
        cmd="set_charge_threshold_enabled",
        id=61,
        service="power",
        enabled=threshold["enabled"],
    )
    reply = daemon.reply_to(61, timeout=15)
    check(
        reply is not None and reply.get("ok") is True,
        "writing the threshold back to its current value is accepted",
    )
    daemon.close()


def test_the_hyprland_state_is_the_compositors_own_json():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=90, services=["hyprland"])
    daemon.reply_to(90, timeout=25)
    _, message = daemon.wait_for(is_state("hyprland"), timeout=10)
    if message is None:
        print("  skip no hyprland state; no compositor on this seat")
        daemon.close()
        return

    state = message["state"]
    for field in (
        "connected",
        "windows",
        "workspaces",
        "workspaces_numbered",
        "active_workspace",
        "active_window",
        "monitors",
        "layers",
    ):
        check(field in state, "hyprland state carries %s" % field)

    check(state["connected"] is True, "a state is only published once the socket answered")

    numbered = [ws["id"] for ws in state["workspaces_numbered"]]
    check(
        all(1 <= i <= 100 for i in numbered),
        "workspaces_numbered holds only ids the bar draws (got %s)" % numbered,
    )
    check(
        set(numbered) <= {ws["id"] for ws in state["workspaces"]},
        "the numbered view is a subset of the whole workspace list",
    )

    # the port is meant to be invisible to a consumer that was reading hyprctl -j
    if state["windows"]:
        window = state["windows"][0]
        for field in ("address", "workspace", "size", "at", "class", "initialClass", "pid"):
            check(field in window, "a client carries hyprctl's %s" % field)
        check(
            isinstance(window["workspace"], dict) and "id" in window["workspace"],
            "a client's workspace is the {id, name} object hyprctl prints",
        )
    else:
        print("  skip no windows open to check the client shape against")

    if state["monitors"]:
        monitor = state["monitors"][0]
        for field in ("name", "activeWorkspace", "refreshRate", "reserved", "transform"):
            check(field in monitor, "a monitor carries hyprctl's %s" % field)

    daemon.send(cmd="dispatch", id=91, service="hyprland", args="killactive")
    reply = daemon.reply_to(91, timeout=10)
    check(
        reply is not None and reply.get("error") == "unknown_command",
        "hyprland is read-only: a dispatch is refused rather than run",
    )
    daemon.close()


def test_the_brightness_state_is_a_fraction_of_the_panels_own_units():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=100, services=["brightness"])
    daemon.reply_to(100, timeout=25)
    _, message = daemon.wait_for(is_state("brightness"), timeout=5)
    if message is None:
        print("  skip no brightness state")
        daemon.close()
        return

    panels = message["state"]["panels"]
    check("panels" in message["state"], "brightness state carries panels")
    for panel in panels:
        for field in ("id", "connector", "backend", "brightness", "raw", "raw_max"):
            check(field in panel, "panel %s carries %s" % (panel.get("id"), field))
        check(
            panel["backend"] in ("logind", "ddc"),
            "panel %s names a backend the document lists" % panel["id"],
        )
        check(
            panel["raw_max"] > 0,
            "panel %s reports a max no fraction can be taken against" % panel["id"],
        )
        check(
            abs(panel["brightness"] - panel["raw"] / panel["raw_max"]) < 1e-6,
            "panel %s: brightness is raw over raw_max" % panel["id"],
        )

    # Refused on the id, so nothing reaches a backlight. A panel that does exist would
    # be moved by this, which is the one thing this suite will not do.
    daemon.send(
        cmd="set_brightness",
        service="brightness",
        id=101,
        panel="no-such-panel",
        value=0.5,
    )
    reply = daemon.reply_to(101, timeout=10)
    check(
        reply is not None and reply.get("ok") is False,
        "a set_brightness for an unknown panel is refused rather than applied elsewhere",
    )

    daemon.send(cmd="set_brightness", service="brightness", id=102, panel="eDP-1")
    reply = daemon.reply_to(102, timeout=10)
    check(
        reply is not None and reply.get("error") == "bad_request",
        "a set_brightness with no value is bad_request",
    )
    daemon.close()


def test_the_bluetooth_state_derives_what_the_qml_used_to_scan_for():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=110, services=["bluetooth"])
    daemon.reply_to(110, timeout=25)
    _, message = daemon.wait_for(is_state("bluetooth"), timeout=5)
    if message is None:
        print("  skip no bluetooth state; bluez did not answer")
        daemon.close()
        return

    state = message["state"]
    for field in ("available", "powered", "discovering", "connected", "connected_count"):
        check(field in state, "bluetooth state carries %s" % field)

    check(
        state["available"] == (len(state["adapters"]) > 0),
        "available agrees with the adapter list",
    )
    connected = [d for d in state["devices"] if d["connected"]]
    check(state["connected"] == bool(connected), "connected agrees with the device list")
    check(
        state["connected_count"] == len(connected),
        "connected_count agrees with the device list",
    )
    if state["adapter"] is not None:
        check(
            state["powered"] == state["adapter"]["powered"],
            "powered is the default adapter's",
        )
        check(
            state["adapter"]["power_state"]
            in ("on", "off", "off-enabling", "on-disabling", "off-blocked", "unknown"),
            "power_state is one the document names",
        )

    for device in state["devices"]:
        check(device["alias"] != "", "device %s always has an alias" % device["path"])
        check(
            device["battery"] is None or 0 <= device["battery"] <= 100,
            "device %s reports a percentage, not a fraction" % device["path"],
        )

    rfkill = state["rfkill"]
    bluetooth = [e for e in rfkill["entries"] if e["kind"] == "bluetooth"]
    check(
        rfkill["soft_blocked"] == any(e["soft_blocked"] for e in bluetooth),
        "rfkill.soft_blocked is the bluetooth switches only",
    )
    check(
        rfkill["hard_blocked"] == any(e["hard_blocked"] for e in bluetooth),
        "rfkill.hard_blocked is the bluetooth switches only",
    )
    daemon.close()


def test_a_bluetooth_command_naming_no_device_is_refused_before_bluez_is_asked():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=120, services=["bluetooth"])
    daemon.reply_to(120, timeout=25)

    for request_id, request, expected in (
        (121, dict(cmd="connect", service="bluetooth"), "bad_request"),
        (122, dict(cmd="set_powered", service="bluetooth"), "bad_request"),
        (123, dict(cmd="unpair", service="bluetooth"), "unknown_command"),
    ):
        daemon.send(id=request_id, **request)
        reply = daemon.reply_to(request_id, timeout=10)
        check(
            reply is not None and reply.get("error") == expected,
            "%s answers %s" % (request["cmd"], expected),
        )

    # A path shaped like BlueZ's but belonging to no object: refused, and nothing on the
    # seat is connected or disconnected on the way to finding that out.
    daemon.send(
        cmd="disconnect",
        service="bluetooth",
        id=124,
        device="/org/bluez/hci0/dev_00_00_00_00_00_00",
    )
    reply = daemon.reply_to(124, timeout=15)
    check(
        reply is not None and reply.get("ok") is False,
        "a command for a device that does not exist is refused",
    )
    daemon.close()


def test_unsubscribe_stops_the_service_and_poll_rate_is_taken():
    daemon = Daemon()
    daemon.send(cmd="subscribe", id=70, services=["power"])
    daemon.reply_to(70, timeout=25)

    daemon.send(cmd="set_poll_rate", id=71, factor=2)
    reply = daemon.reply_to(71, timeout=10)
    check(reply is not None and reply.get("ok") is True, "set_poll_rate is accepted")

    daemon.send(cmd="set_poll_rate", id=72, factor=0)
    reply = daemon.reply_to(72, timeout=10)
    check(
        reply is not None and reply.get("ok") is True,
        "a factor below 1 is clamped rather than rejected",
    )

    daemon.send(cmd="unsubscribe", id=73, services=["power"])
    check(daemon.reply_to(73, timeout=10) is not None, "unsubscribe is accepted")

    daemon.send(cmd="get_state", id=74, service="power")
    reply = daemon.reply_to(74, timeout=10)
    check(
        reply is not None and reply.get("error") == "not_subscribed",
        "a command to an unsubscribed service is refused",
    )
    daemon.close()


def test_quit_replies_before_it_exits():
    daemon = Daemon()
    daemon.wait_for(lambda m: m.get("type") == "hello", timeout=10)
    daemon.send(cmd="quit", id=80)
    code = daemon.close()
    check(code == 0, "quit exits 0 (got %s)" % code)
    check(
        any(m.get("type") == "reply" and m.get("id") == 80 for m in daemon.seen()),
        "the reply to quit reached the consumer before the process went away",
    )


def main():
    if not os.path.isfile(SHELLD):
        print("no koompi-shelld at %s; build it first" % SHELLD)
        return 2

    for test in (
        test_hello_is_first_and_nothing_follows_it_unasked,
        test_subscribe_emits_state_before_its_reply,
        test_subscribing_twice_re_emits_rather_than_going_quiet,
        test_get_state_re_emits_before_replying_and_serial_advances,
        test_the_error_codes_are_the_ones_the_document_names,
        test_an_access_point_that_is_not_in_the_snapshot_is_refused,
        test_the_network_state_carries_what_the_qml_binds_to,
        test_the_charge_threshold_write_path_answers_without_moving_the_pack,
        test_the_hyprland_state_is_the_compositors_own_json,
        test_the_brightness_state_is_a_fraction_of_the_panels_own_units,
        test_the_bluetooth_state_derives_what_the_qml_used_to_scan_for,
        test_a_bluetooth_command_naming_no_device_is_refused_before_bluez_is_asked,
        test_unsubscribe_stops_the_service_and_poll_rate_is_taken,
        test_quit_replies_before_it_exits,
    ):
        print(test.__name__)
        test()

    print(
        "%d checks failed" % len(failures)
        if failures
        else "koompi-shelld conformance passed"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
