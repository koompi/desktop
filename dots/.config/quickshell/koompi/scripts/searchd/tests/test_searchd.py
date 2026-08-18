#!/usr/bin/env python3
"""Conformance suite for the searchd NDJSON protocol.

PROTOCOL.md, not the Zig source, is the contract - the same discipline
audiod/tests/test_audiod.py and tests/test_daemon.py hold their daemons to.

Run: SEARCHD=./zig-out/bin/searchd python3 tests/test_searchd.py   (after `zig build`)

Uses a real temp $HOME so the `files` domain has something deterministic to walk,
rather than the machine's actual home directory - this suite never reads real user
files or real clipboard content.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SEARCHD = os.environ.get("SEARCHD", os.path.join(HERE, "..", "zig-out", "bin", "searchd"))
SRC_DIR = os.path.join(HERE, "..", "src")

failures = []


def check(condition, message):
    if condition:
        print("  ok   %s" % message)
    else:
        print("  FAIL %s" % message)
        failures.append(message)


class Daemon:
    """Drives one searchd over stdio, pulling replies out in request order."""

    def __init__(self, home):
        env = dict(os.environ)
        env["HOME"] = home
        self.proc = subprocess.Popen(
            [SEARCHD],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
        )

    def recv(self):
        line = self.proc.stdout.readline()
        if line == "":
            raise EOFError("searchd closed stdout; stderr:\n" + self.proc.stderr.read())
        return json.loads(line)

    def send(self, obj):
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()

    def call(self, obj):
        self.send(obj)
        return self.recv()

    def close(self):
        try:
            self.call({"cmd": "quit", "id": -1})
        except (BrokenPipeError, EOFError):
            pass
        self.proc.wait(timeout=5)


def with_daemon(home_files, fn):
    with tempfile.TemporaryDirectory() as home:
        for rel, content in home_files.items():
            path = os.path.join(home, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(content)
        d = Daemon(home)
        try:
            fn(d)
        finally:
            d.close()


def test_startup_sequence():
    def run(d):
        hello = d.recv()
        check(hello["type"] == "hello", "first line is hello")
        check(hello["protocol"] == 1, "protocol is 1")
        check(hello["daemon"] == "searchd", 'daemon is "searchd"')
        check(set(hello["services"]) == {"files", "clipboard", "apps"}, "hello advertises all three services")

        files_state = d.recv()
        check(files_state == {"type": "state", "service": "files", "ready": True, "entryCount": 1, "buildMs": files_state.get("buildMs")}, "files state matches the one indexable file")
        check(isinstance(files_state["buildMs"], (int, float)), "files buildMs is a number")

        clip_state = d.recv()
        check(clip_state == {"type": "state", "service": "clipboard", "ready": True, "entryCount": 0}, "clipboard starts empty and ready")

        apps_state = d.recv()
        check(apps_state == {"type": "state", "service": "apps", "ready": True, "entryCount": 0}, "apps starts empty and ready")

    with_daemon({"Documents/report.pdf": "x"}, run)


def test_ping_and_quit():
    def run(d):
        d.recv(); d.recv(); d.recv(); d.recv()  # hello + 3 states
        reply = d.call({"cmd": "ping", "id": 1})
        check(reply == {"type": "reply", "id": 1, "ok": True}, "ping replies ok, echoing id")

    with_daemon({}, run)


def test_files_search():
    def run(d):
        d.recv(); d.recv(); d.recv(); d.recv()
        reply = d.call({"cmd": "search", "id": 2, "service": "files", "query": "report"})
        check(reply["ok"] is True, "files search ok")
        check(reply["total"] == 1, "files search finds the one report file")
        check(reply["results"][0]["name"] == "report.pdf", "files result carries the right name")
        check(reply["results"][0]["path"].endswith("Documents/report.pdf"), "files result path is absolute and under Documents")

        short = d.call({"cmd": "search", "id": 3, "service": "files", "query": "r"})
        check(short == {"type": "reply", "id": 3, "ok": True, "service": "files", "results": [], "total": 0}, "a query under 2 chars returns empty, matching FileSearch.qml's own floor")

        no_match = d.call({"cmd": "search", "id": 4, "service": "files", "query": "zzznomatch"})
        check(no_match["total"] == 0 and no_match["results"] == [], "no-match query returns an empty, not an error")

    with_daemon({"Documents/report.pdf": "x", "Documents/notes.txt": "y"}, run)


def test_clipboard_and_apps_update_and_search():
    def run(d):
        d.recv(); d.recv(); d.recv(); d.recv()

        upd = d.call({"cmd": "update", "id": 5, "service": "clipboard", "entries": [
            {"id": "1\thello world", "name": "hello world"},
            {"id": "2\tfoo bar", "name": "foo bar"},
        ]})
        check(upd == {"type": "reply", "id": 5, "ok": True, "service": "clipboard", "count": 2}, "clipboard update replaces the dataset and reports its size")

        reply = d.call({"cmd": "search", "id": 6, "service": "clipboard", "query": "hello"})
        check(reply["ok"] and len(reply["results"]) == 1 and reply["results"][0]["id"] == "1\thello world", "clipboard search matches and returns the raw id")

        upd2 = d.call({"cmd": "update", "id": 7, "service": "apps", "entries": [{"id": "app1.desktop", "name": "Text Editor"}]})
        check(upd2["ok"] and upd2["count"] == 1, "apps update accepted")
        reply2 = d.call({"cmd": "search", "id": 8, "service": "apps", "query": "text"})
        check(reply2["results"][0]["id"] == "app1.desktop", "apps search returns the desktop id")

        bad = d.call({"cmd": "update", "id": 9, "service": "files", "entries": []})
        check(bad == {"type": "reply", "id": 9, "ok": False, "error": "bad_request", "message": bad.get("message")}, '"files" rejects update rather than silently ignoring it')

    with_daemon({}, run)


def test_error_vocabulary():
    def run(d):
        d.recv(); d.recv(); d.recv(); d.recv()

        no_id = d.call({"cmd": "search", "service": "files", "query": "x"})
        check(no_id == {"type": "reply", "id": None, "ok": False, "error": "bad_request", "message": no_id.get("message")}, 'search without "id" is bad_request, id echoed null')

        unknown_svc = d.call({"cmd": "search", "id": 10, "service": "bogus", "query": "x"})
        check(unknown_svc["error"] == "unknown_service", "an unrecognized service is unknown_service")

        unknown_cmd = d.call({"cmd": "not_a_command", "id": 11})
        check(unknown_cmd["error"] == "unknown_command", "an unrecognized cmd is unknown_command")

        d.send("not json at all")
        malformed = d.recv()
        check(malformed == {"type": "reply", "id": None, "ok": False, "error": "malformed", "message": malformed.get("message")}, "invalid JSON is malformed with a null id")

    with_daemon({}, run)


def test_privacy_no_logging_of_clipboard_content():
    """clip.zig doesn't exist as a separate file - store.zig is the shared
    clipboard/apps path. Assert nothing in it (or main.zig's dispatch of it)
    can reach a std.log/std.debug print carrying query or entry text."""
    src = ""
    for name in ("store.zig", "main.zig"):
        with open(os.path.join(SRC_DIR, name)) as f:
            src += f.read()

    log_calls = re.findall(r"std\.(?:log|debug)\.\w+\([^)]*\)", src, re.DOTALL)
    check(len(log_calls) == 0, "no std.log/std.debug call exists anywhere in store.zig or main.zig")

    check("unreachable" not in open(os.path.join(SRC_DIR, "store.zig")).read(), "store.zig contains no unreachable on entry-derived data")


def main():
    if not os.path.isfile(SEARCHD):
        print("searchd binary not found at %s; run 'zig build' first" % SEARCHD)
        sys.exit(1)

    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            print("== %s ==" % name)
            fn()

    print("\n%d failure(s)" % len(failures))
    if failures:
        print("failed:")
        for f in failures:
            print("  - %s" % f)
        sys.exit(1)
    print("all checks passed")


if __name__ == "__main__":
    main()
