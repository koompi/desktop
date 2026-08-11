#!/usr/bin/env python3
"""Conformance suite for the audiod NDJSON protocol.

PROTOCOL.md, not either implementation, is the contract. This suite is what holds
both sides to it, the way tests/test_daemon.py holds the two global menu daemons to
theirs. AUDIOD points it at the binary under test.

It runs against the live PipeWire session, because a fake that answers the daemon's
own assumptions proves nothing about the C boundary. It is read-only against the
seat by construction:

  - the volume it writes is the value the daemon just reported for that node, so the
    write path is exercised and the amplitude is left where it was,
  - the default sink it sets is the sink that is already default,
  - the only volume it moves is that of a silent stream it started itself.

Run: AUDIOD=./zig-out/bin/audiod python3 tests/test_audiod.py   (after `zig build`)
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIOD = os.environ.get("AUDIOD", os.path.join(HERE, "..", "zig-out", "bin", "audiod"))

failures = []


def check(condition, message):
    if condition:
        print("  ok   %s" % message)
    else:
        print("  FAIL %s" % message)
        failures.append(message)


def wpctl(*args):
    return subprocess.run(
        ["wpctl"] + list(args), capture_output=True, text=True, check=True
    ).stdout


def wpctl_default_name(target):
    match = re.search(r'node\.name = "([^"]+)"', wpctl("inspect", target))
    return match.group(1) if match else None


def wpctl_raw_amplitudes(node_id):
    """The linear amplitude PipeWire actually stores, straight from pw-dump."""
    dump = json.loads(
        subprocess.run(
            ["pw-dump", str(node_id)], capture_output=True, text=True, check=True
        ).stdout
    )
    for obj in dump:
        for props in obj.get("info", {}).get("params", {}).get("Props", []):
            if "channelVolumes" in props:
                return props["channelVolumes"]
    return None


class Daemon:
    """Drives one audiod over stdio, collecting every line it emits."""

    def __init__(self, env=None):
        self.messages = []
        self.lock = threading.Lock()
        self.proc = subprocess.Popen(
            [AUDIOD],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
        )
        self.reader = threading.Thread(target=self._pump, daemon=True)
        self.reader.start()

    def _pump(self):
        for line in self.proc.stdout:
            line = line.strip()
            if not line:
                continue
            with self.lock:
                self.messages.append(json.loads(line))

    def snapshot(self):
        with self.lock:
            return list(self.messages)

    def send_raw(self, text):
        self.proc.stdin.write(text + "\n")
        self.proc.stdin.flush()

    def send(self, **command):
        self.send_raw(json.dumps(command))

    def wait_for(self, predicate, timeout=10.0, since=0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            for message in self.snapshot()[since:]:
                if predicate(message):
                    return message
            time.sleep(0.02)
        return None

    def reply(self, request_id, timeout=10.0):
        return self.wait_for(
            lambda m: m["type"] == "reply" and m.get("id") == request_id, timeout
        )

    def request(self, cmd, request_id, **args):
        self.send(cmd=cmd, id=request_id, **args)
        return self.reply(request_id)

    def stop(self):
        try:
            self.proc.stdin.close()
        except OSError:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait(timeout=5)


def silent_wav(directory):
    """Eight seconds of digital silence: a real stream nobody has to hear."""
    path = os.path.join(directory, "silence.wav")
    with wave.open(path, "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(48000)
        handle.writeframes(b"\x00" * (48000 * 2 * 2 * 8))
    return path


NODE_FIELDS = {
    "id": int,
    "name": str,
    "media_class": str,
    "is_sink": bool,
    "is_stream": bool,
    "is_default": bool,
    "ready": bool,
    "channel_volumes": list,
}
OPTIONAL_NODE_FIELDS = {
    "serial": int,
    "description": str,
    "nickname": str,
    "application_name": str,
    "volume": float,
    "mute": bool,
}
BUCKETS = ("output_devices", "input_devices", "output_streams", "input_streams")


def node_shape_problems(node):
    problems = []
    for field, kind in NODE_FIELDS.items():
        if field not in node:
            problems.append("%s missing" % field)
        elif not isinstance(node[field], kind):
            problems.append("%s is %s" % (field, type(node[field]).__name__))
    for field, kind in OPTIONAL_NODE_FIELDS.items():
        if field in node and node[field] is not None:
            if kind is float and isinstance(node[field], int):
                continue
            if not isinstance(node[field], kind):
                problems.append("%s is %s" % (field, type(node[field]).__name__))
    if node.get("ready"):
        if node.get("volume") is None:
            problems.append("ready but volume is null")
        if node.get("mute") is None:
            problems.append("ready but mute is null")
        if not node["channel_volumes"]:
            problems.append("ready but channel_volumes is empty")
    return problems


def all_nodes(state):
    return [node for bucket in BUCKETS for node in state[bucket]]


# --- tests ------------------------------------------------------------------


def test_startup_lines(daemon):
    print("startup: hello, then state")
    messages = daemon.snapshot()
    hello = messages[0] if messages else {}
    check(hello.get("type") == "hello", "the first line is hello: %r" % hello.get("type"))
    check(hello.get("protocol") == 1, "hello declares protocol 1: %r" % hello.get("protocol"))
    check(hello.get("daemon") == "audiod", "hello names the daemon: %r" % hello.get("daemon"))
    check(
        isinstance(hello.get("version"), str) and isinstance(hello.get("pipewire"), str),
        "hello carries a daemon version and the linked pipewire version: %r / %r"
        % (hello.get("version"), hello.get("pipewire")),
    )

    state = messages[1] if len(messages) > 1 else {}
    check(state.get("type") == "state", "the second line is state: %r" % state.get("type"))
    check(state.get("ready") is True, "the initial state is ready")
    check(state.get("serial") == 1, "the first snapshot serial is 1: %r" % state.get("serial"))
    check(
        all(isinstance(state.get(bucket), list) for bucket in BUCKETS),
        "state carries all four node lists",
    )
    return state


def test_node_shape(state):
    print("state: node objects and bucket invariants")
    problems = []
    for node in all_nodes(state):
        problems += ["%s: %s" % (node.get("name"), p) for p in node_shape_problems(node)]
    check(not problems, "every node matches the documented shape: %s" % (problems or "clean"))

    ids = [node["id"] for node in all_nodes(state)]
    check(len(ids) == len(set(ids)), "a node appears in exactly one bucket")
    check(
        all(
            [n["id"] for n in state[bucket]] == sorted(n["id"] for n in state[bucket])
            for bucket in BUCKETS
        ),
        "each bucket is sorted by id",
    )

    expected = {
        "output_devices": (True, False),
        "input_devices": (False, False),
        "output_streams": (True, True),
        "input_streams": (False, True),
    }
    wrong = [
        (bucket, node["name"])
        for bucket, (is_sink, is_stream) in expected.items()
        for node in state[bucket]
        if (node["is_sink"], node["is_stream"]) != (is_sink, is_stream)
    ]
    check(not wrong, "is_sink and is_stream agree with the bucket: %s" % (wrong or "clean"))
    check(
        not any(node["is_default"] for node in state["output_streams"] + state["input_streams"]),
        "no stream claims to be a default",
    )


def test_defaults_match_wpctl(state):
    print("state: defaults against wpctl, the external reference")
    for key, target, bucket in (
        ("default_sink", "@DEFAULT_AUDIO_SINK@", "output_devices"),
        ("default_source", "@DEFAULT_AUDIO_SOURCE@", "input_devices"),
    ):
        expected = wpctl_default_name(target)
        check(
            state.get(key) == expected,
            "%s matches wpctl: %r vs %r" % (key, state.get(key), expected),
        )
        flagged = [node["name"] for node in state[bucket] if node["is_default"]]
        check(
            flagged == [expected],
            "exactly the wpctl default carries is_default in %s: %r" % (bucket, flagged),
        )


def test_volume_matches_pipewire(state):
    print("state: volume is the cube root of the stored amplitude")
    checked = 0
    for node in state["output_devices"] + state["input_devices"]:
        if not node["ready"]:
            continue
        raw = wpctl_raw_amplitudes(node["id"])
        if raw is None:
            continue
        checked += 1
        expected = [round(a ** (1.0 / 3.0), 4) for a in raw]
        got = [round(v, 4) for v in node["channel_volumes"]]
        check(got == expected, "%s channel_volumes: %r vs %r" % (node["name"], got, expected))
    check(checked > 0, "at least one device was compared against pw-dump: %d" % checked)


def test_ping_and_get_state(daemon):
    print("commands: ping and get_state")
    check(daemon.request("ping", 1) == {"type": "reply", "id": 1, "ok": True},
          "ping replies ok with the id echoed back")

    before = len(daemon.snapshot())
    reply = daemon.request("get_state", 2)
    check(reply is not None and reply["ok"], "get_state replies ok")
    tail = daemon.snapshot()[before:]
    states = [m for m in tail if m["type"] == "state"]
    check(len(states) == 1, "get_state emits exactly one state: %d" % len(states))
    if states:
        check(states[0]["serial"] > 1, "the snapshot serial advanced: %r" % states[0]["serial"])
        check(
            tail.index(states[0]) < tail.index(reply),
            "the state comes before the reply",
        )

    daemon.send_raw("")
    check(daemon.request("ping", 3) is not None, "a blank line is ignored, not answered")


def test_malformed_input(daemon):
    print("commands: malformed input")
    for label, payload in (
        ("not JSON", "this is not json"),
        ("a JSON array", "[1,2,3]"),
        ("a bare string", '"hello"'),
    ):
        before = len(daemon.snapshot())
        daemon.send_raw(payload)
        reply = daemon.wait_for(lambda m: m["type"] == "reply", since=before)
        check(
            reply is not None and reply["ok"] is False and reply["error"] == "malformed",
            "%s is malformed: %r" % (label, reply),
        )
        check(reply is not None and reply.get("id") is None, "an unreadable line replies with a null id")

    daemon.send(id=4)
    check(
        (daemon.reply(4) or {}).get("error") == "malformed",
        "an object with no cmd is malformed",
    )
    daemon.send(cmd=7, id=5)
    check(
        (daemon.reply(5) or {}).get("error") == "malformed",
        "a non-string cmd is malformed",
    )

    before = len(daemon.snapshot())
    daemon.send_raw('{"cmd":"ping","pad":"' + "x" * (80 * 1024) + '"}')
    reply = daemon.wait_for(lambda m: m["type"] == "reply", since=before)
    check(
        reply is not None and reply.get("error") == "malformed",
        "a line past the input buffer is malformed rather than split: %r" % reply,
    )
    check(daemon.request("ping", 6) is not None, "the daemon resynchronises after an oversized line")


def test_unknown_command(daemon):
    print("commands: unknown command")
    reply = daemon.request("set_the_house_on_fire", 7)
    check(reply is not None and reply["ok"] is False, "an unknown command fails")
    check(
        reply is not None and reply["error"] == "unknown_command",
        "the error code is unknown_command: %r" % (reply or {}).get("error"),
    )
    check(
        reply is not None and reply.get("message") == "set_the_house_on_fire",
        "the message names the command that was sent: %r" % (reply or {}).get("message"),
    )


def test_bad_requests(daemon, state):
    print("commands: argument validation")
    sink = next(n for n in state["output_devices"] if n["is_default"])
    cases = [
        ("set_volume with no node", {"cmd": "set_volume", "volume": 0.5}, "bad_request"),
        ("set_volume with a string node", {"cmd": "set_volume", "node": "85", "volume": 0.5}, "bad_request"),
        ("set_volume with no volume", {"cmd": "set_volume", "node": sink["id"]}, "bad_request"),
        ("set_volume with a string volume", {"cmd": "set_volume", "node": sink["id"], "volume": "loud"}, "bad_request"),
        ("set_volume above the cap", {"cmd": "set_volume", "node": sink["id"], "volume": 3.0}, "bad_request"),
        ("set_volume below zero", {"cmd": "set_volume", "node": sink["id"], "volume": -0.1}, "bad_request"),
        ("set_mute with no mute", {"cmd": "set_mute", "node": sink["id"]}, "bad_request"),
        ("set_mute with a string mute", {"cmd": "set_mute", "node": sink["id"], "mute": "yes"}, "bad_request"),
        ("set_default_sink with no name", {"cmd": "set_default_sink"}, "bad_request"),
        ("set_default_sink with a number name", {"cmd": "set_default_sink", "name": 85}, "bad_request"),
        ("set_volume on a node that does not exist", {"cmd": "set_volume", "node": 999999, "volume": 0.5}, "unknown_node"),
        ("set_mute on a node that does not exist", {"cmd": "set_mute", "node": 999999, "mute": False}, "unknown_node"),
        ("set_default_sink on a name that does not exist", {"cmd": "set_default_sink", "name": "no.such.sink"}, "unknown_node"),
        ("set_default_source on a sink name", {"cmd": "set_default_source", "name": sink["name"]}, "unknown_node"),
    ]
    for index, (label, command, expected) in enumerate(cases, start=100):
        command = dict(command, id=index)
        daemon.send(**command)
        reply = daemon.reply(index)
        check(
            reply is not None and reply["ok"] is False and reply["error"] == expected,
            "%s -> %s: %r" % (label, expected, reply),
        )


def test_volume_write_restores(daemon, state):
    print("writes: setting a node's volume to the value it already holds")
    sink = next(n for n in state["output_devices"] if n["is_default"])
    before = wpctl_raw_amplitudes(sink["id"])
    reply = daemon.request("set_volume", 200, node=sink["id"], volume=sink["volume"])
    check(reply is not None and reply["ok"], "the write is accepted: %r" % reply)
    time.sleep(0.5)
    after = wpctl_raw_amplitudes(sink["id"])
    check(before == after, "the sink amplitude is where it was: %r vs %r" % (before, after))


def test_set_default_sink_to_the_current_default(daemon, state):
    print("writes: setting the default sink to the sink that is already default")
    sink = next(n for n in state["output_devices"] if n["is_default"])
    reply = daemon.request("set_default_sink", 201, name=sink["name"])
    check(reply is not None and reply["ok"], "the write is accepted: %r" % reply)
    time.sleep(0.5)
    check(
        wpctl_default_name("@DEFAULT_AUDIO_SINK@") == sink["name"],
        "the seat's default sink is unchanged",
    )

    source = next(n for n in state["input_devices"] if n["is_default"])
    reply = daemon.request("set_default_source", 202, name=source["name"])
    check(reply is not None and reply["ok"], "the same holds for the source: %r" % reply)
    time.sleep(0.5)
    check(
        wpctl_default_name("@DEFAULT_AUDIO_SOURCE@") == source["name"],
        "the seat's default source is unchanged",
    )


def test_stream_lifecycle(daemon, wav):
    print("events: a stream appearing, changing and going away")
    before = len(daemon.snapshot())
    player = subprocess.Popen(["pw-play", wav], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        added = daemon.wait_for(
            lambda m: m["type"] == "node_added"
            and m["node"]["media_class"] == "Stream/Output/Audio",
            timeout=10,
            since=before,
        )
        check(added is not None, "node_added arrives for the new output stream")
        if added is None:
            return
        node = added["node"]
        check(node["is_sink"] and node["is_stream"], "it is classified as an output stream")
        check(
            node.get("application_name") == "pw-play",
            "it carries application.name: %r" % node.get("application_name"),
        )

        ready = daemon.wait_for(
            lambda m: m["type"] == "node_changed"
            and m["node"]["id"] == node["id"]
            and m["node"]["ready"],
            timeout=10,
            since=before,
        )
        check(ready is not None, "node_changed reports the stream's volume once published")

        reply = daemon.request("get_state", 203)
        listed = daemon.wait_for(
            lambda m: m["type"] == "state"
            and any(n["id"] == node["id"] for n in m["output_streams"]),
            timeout=5,
            since=before,
        )
        check(listed is not None, "the stream is in output_streams of a fresh snapshot")
        check(reply is not None and reply["ok"], "get_state still replies ok")

        # The only volume this suite moves belongs to the silent stream it started.
        # WirePlumber persists a stream's volume per application, so the target has
        # to differ from whatever it currently is, and has to be put back.
        original = ready["node"]["volume"] if ready else node["volume"]
        target = round(original / 2, 4) if original and original > 0.1 else 0.5
        mark = len(daemon.snapshot())
        subprocess.run(["wpctl", "set-volume", str(node["id"]), str(target)], check=True)
        observed = daemon.wait_for(
            lambda m: m["type"] == "node_changed"
            and m["node"]["id"] == node["id"]
            and abs((m["node"]["volume"] or 0) - target) < 0.01,
            timeout=10,
            since=mark,
        )
        check(
            observed is not None,
            "an external wpctl volume change is observed as node_changed: %r -> %r"
            % (original, target),
        )

        mark = len(daemon.snapshot())
        subprocess.run(["wpctl", "set-volume", str(node["id"]), str(original)], check=True)
        restored = daemon.wait_for(
            lambda m: m["type"] == "node_changed"
            and m["node"]["id"] == node["id"]
            and abs((m["node"]["volume"] or 0) - original) < 0.01,
            timeout=10,
            since=mark,
        )
        check(restored is not None, "and the stream's volume is put back where it was")
    finally:
        player.terminate()
        player.wait(timeout=5)

    removed = daemon.wait_for(
        lambda m: m["type"] == "node_removed" and m["id"] == node["id"],
        timeout=10,
        since=before,
    )
    check(removed is not None, "node_removed arrives when the stream stops")


def test_quit_exits_clean(daemon):
    print("lifecycle: quit")
    reply = daemon.request("quit", 300)
    check(reply is not None and reply["ok"], "quit replies ok: %r" % reply)
    try:
        code = daemon.proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        daemon.proc.kill()
        code = None
    check(code == 0, "the daemon exits 0: %r" % code)
    trailing = [m for m in daemon.snapshot() if m["type"] == "unavailable"]
    check(not trailing, "tearing itself down is not reported as pipewire going away")


def test_unavailable_rather_than_hanging():
    print("lifecycle: no pipewire to talk to")
    for label, overrides in (
        ("PIPEWIRE_REMOTE points nowhere", {"PIPEWIRE_REMOTE": "audiod-no-such-socket"}),
        ("XDG_RUNTIME_DIR has no pipewire socket", None),
    ):
        with tempfile.TemporaryDirectory() as runtime:
            env = dict(os.environ)
            env.pop("PIPEWIRE_REMOTE", None)
            if overrides is None:
                env["XDG_RUNTIME_DIR"] = runtime
            else:
                env.update(overrides)
            started = time.time()
            proc = subprocess.Popen(
                [AUDIOD], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, text=True, env=env
            )
            try:
                out, _ = proc.communicate(timeout=20)
            except subprocess.TimeoutExpired:
                proc.kill()
                out, _ = proc.communicate()
                check(False, "%s: the daemon hung instead of reporting" % label)
                continue
            elapsed = time.time() - started
            messages = [json.loads(line) for line in out.splitlines() if line.strip()]
            types = [m["type"] for m in messages]
            check(types[:1] == ["hello"], "%s: hello is still emitted first" % label)
            check(
                "unavailable" in types,
                "%s: unavailability is reported: %r" % (label, types),
            )
            reason = next((m["reason"] for m in messages if m["type"] == "unavailable"), None)
            check(
                reason == "connect_failed",
                "%s: the reason is connect_failed: %r" % (label, reason),
            )
            check(proc.returncode == 1, "%s: it exits 1: %r" % (label, proc.returncode))
            check(elapsed < 15, "%s: it exits promptly: %.2fs" % (label, elapsed))


def test_startup_budget_is_bounded():
    print("lifecycle: the startup budget")
    # A zero budget cannot be met even by a healthy server, so this exercises the
    # path that a live-but-unresponsive pipewire would take.
    env = dict(os.environ, AUDIOD_STARTUP_TIMEOUT_MS="0")
    proc = subprocess.Popen(
        [AUDIOD], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, text=True, env=env
    )
    try:
        out, _ = proc.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()
        out, _ = proc.communicate()
        check(False, "a zero budget still hung")
        return
    messages = [json.loads(line) for line in out.splitlines() if line.strip()]
    reason = next((m["reason"] for m in messages if m["type"] == "unavailable"), None)
    check(reason == "startup_timeout", "an exhausted budget reports startup_timeout: %r" % reason)
    check(proc.returncode == 1, "a timed out start exits 1: %r" % proc.returncode)


def main():
    if not os.path.exists(AUDIOD):
        sys.exit("build the daemon first: zig build")
    for tool in ("wpctl", "pw-dump", "pw-play"):
        if subprocess.run(["which", tool], capture_output=True).returncode != 0:
            sys.exit("%s is required as the external reference" % tool)

    with tempfile.TemporaryDirectory() as tmp:
        wav = silent_wav(tmp)
        daemon = Daemon()
        try:
            state = daemon.wait_for(lambda m: m["type"] == "state", timeout=15)
            if state is None:
                sys.exit("the daemon never published a state")
            test_startup_lines(daemon)
            test_node_shape(state)
            test_defaults_match_wpctl(state)
            test_volume_matches_pipewire(state)
            test_ping_and_get_state(daemon)
            test_malformed_input(daemon)
            test_unknown_command(daemon)
            test_bad_requests(daemon, state)
            test_volume_write_restores(daemon, state)
            test_set_default_sink_to_the_current_default(daemon, state)
            test_stream_lifecycle(daemon, wav)
            test_quit_exits_clean(daemon)
        finally:
            daemon.stop()
        test_unavailable_rather_than_hanging()
        test_startup_budget_is_bounded()

    if failures:
        print("\n%d check(s) failed" % len(failures))
        sys.exit(1)
    print("\nall checks passed")


if __name__ == "__main__":
    main()
