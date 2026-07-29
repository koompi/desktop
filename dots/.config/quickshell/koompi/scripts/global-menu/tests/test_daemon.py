#!/usr/bin/env python3
"""End-to-end tests for the global-menu daemon.

The daemon is run in --test mode, which keeps everything except the compositor:
it still owns com.canonical.AppMenu.Registrar and still talks real D-Bus, but
the focused window is chosen over stdin instead of being read from Hyprland.

Two stand-in applications are started on the session bus, one exporting
org.gtk.Menus (GTK) and one exporting com.canonical.dbusmenu (Qt/KDE), and both
are driven the way the shell drives them: read the menu, click an item, assert
the application saw the click.

Run: python3 tests/test_daemon.py   (after `zig build`)
"""

import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DAEMON = os.path.join(HERE, "..", "zig-out", "bin", "global-menu-daemon")

failures = []


def check(condition, message):
    if condition:
        print("  ok   %s" % message)
    else:
        print("  FAIL %s" % message)
        failures.append(message)


def find(items, label):
    for item in items:
        if item.get("label") == label:
            return item
        found = find(item.get("items", []), label)
        if found is not None:
            return found
    return None


class Daemon:
    def __init__(self):
        self.proc = subprocess.Popen(
            [DAEMON, "--test"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self.read()  # the initial empty payload

    def send(self, line):
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def read(self, timeout=10.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if line.strip():
                return json.loads(line)
        raise AssertionError("daemon produced no payload")

    def stop(self):
        self.proc.stdin.close()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def start_mock(script, *args):
    proc = subprocess.Popen(
        [sys.executable, os.path.join(HERE, script)] + [str(a) for a in args],
        stdout=subprocess.PIPE,
        text=True,
    )
    ready = proc.stdout.readline()
    if "READY" not in ready:
        raise AssertionError("%s did not start: %r" % (script, ready))
    return proc


def wait_for(path, predicate, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with open(path) as fh:
            content = fh.read()
        if predicate(content):
            return content
        time.sleep(0.05)
    with open(path) as fh:
        return fh.read()


def test_gtk(daemon, log):
    print("org.gtk.Menus (GTK applications)")
    app = start_mock("mock_gtk_app.py", log)
    try:
        daemon.send(
            "gtk org.koompi.test.GtkApp /org/koompi/test/GtkApp/menus/menubar "
            "/org/koompi/test/GtkApp /org/koompi/test/GtkApp/window/1"
        )
        payload = daemon.read()
        items = payload["items"]

        check([i["label"] for i in items] == ["File", "View"], "menubar is File, View")

        file_items = items[0]["items"]
        labels = [i["label"] for i in file_items]
        check(
            labels == ["New Window", "Open...", "", "Print", "Quit"],
            "sections are spliced in order with a separator: %s" % labels,
        )
        check(file_items[2]["sep"] is True, "the section boundary is a separator")
        check(find(items, "Print")["enabled"] is False, "a disabled action is greyed out")
        check(find(items, "Deep One" or "") is None, "unknown labels are not invented")
        check(find(items, "Deep Item") is not None, "a nested submenu is resolved")

        sidebar = find(items, "Show Sidebar")
        check(sidebar["toggle"] and sidebar["checked"], "boolean state renders as a check")
        grid = find(items, "Grid")
        list_item = find(items, "List")
        check(grid["toggle"] and grid["checked"], "the selected radio entry is checked")
        check(list_item["toggle"] and not list_item["checked"], "the other radio entry is not")

        check(all("_" not in i["label"] for i in items), "mnemonics are stripped")
        check(items[0].get("sub") is True, "a GTK submenu is marked as one")
        check(find(items, "Quit").get("sub") is None, "a GTK leaf is not")

        daemon.send("activate %d" % find(items, "Quit")["id"])
        daemon.send("activate %d" % find(items, "List")["id"])
        content = wait_for(log, lambda c: "quit" in c and "layout" in c)
        check("quit -\n" in content, "clicking Quit invoked app.quit")
        check("layout 'list'\n" in content, "clicking List invoked win.layout('list')")
    finally:
        app.terminate()
        app.wait(timeout=5)


def test_dbusmenu(daemon, log):
    print("com.canonical.dbusmenu (Qt/KDE applications)")
    app = start_mock("mock_dbusmenu_app.py", log, 4242)
    try:
        registered = subprocess.run(
            [
                "gdbus", "call", "--session",
                "--dest", "com.canonical.AppMenu.Registrar",
                "--object-path", "/com/canonical/AppMenu/Registrar",
                "--method", "com.canonical.AppMenu.Registrar.GetMenuForWindow",
                "4242",
            ],
            capture_output=True,
            text=True,
        )
        check(
            "/MenuBar" in registered.stdout,
            "the daemon's registrar answers GetMenuForWindow: %s"
            % (registered.stdout or registered.stderr).strip(),
        )

        daemon.send("dbusmenu org.koompi.test.QtApp /MenuBar")
        payload = daemon.read()
        items = payload["items"]

        check([i["label"] for i in items] == ["File", "Tools"], "invisible entries are dropped")
        file_items = items[0]["items"]
        check(
            [i["label"] for i in file_items] == ["New", "", "Quit"],
            "the layout keeps separators in place",
        )
        check(file_items[1]["sep"] is True, "separator type is honoured")
        check(file_items[2]["enabled"] is False, "a disabled entry is greyed out")

        tools = items[1]
        check(tools.get("items", []) == [], "a lazily built submenu starts empty")
        # Without this the shell cannot tell an empty submenu from a leaf, and
        # clicking Tools would activate it instead of opening it.
        check(tools.get("sub") is True, "an empty submenu still says it is one")
        check(items[0].get("sub") is True, "a populated submenu says so too")
        check(find(items, "New").get("sub") is None, "a leaf is not marked as a submenu")

        daemon.send("open %d" % tools["id"])
        patch = daemon.read()
        check(patch.get("patch") == tools["id"], "opening it produces a patch for that item")
        check(
            [i["label"] for i in patch["items"]] == ["Preferences"],
            "the patch carries the entries the app built on AboutToShow",
        )
        pref = patch["items"][0]
        check(pref["toggle"] and pref["checked"], "toggle state survives the patch")
        check(pref.get("sub") is None, "a patched leaf is not marked as a submenu")

        daemon.send("activate %d" % pref["id"])
        content = wait_for(log, lambda c: "event 7 clicked" in c)
        check("event 7 clicked" in content, "clicking a patched entry sends Event(clicked)")

        daemon.send("activate %d" % find(items, "New")["id"])
        content = wait_for(log, lambda c: "event 2 clicked" in c)
        check("event 2 clicked" in content, "clicking a top-level entry sends Event(clicked)")
    finally:
        app.terminate()
        app.wait(timeout=5)


def test_no_menu(daemon):
    print("applications with no exported menu")
    daemon.send("dbusmenu org.koompi.test.Nothing /MenuBar")
    payload = daemon.read()
    check(payload["items"] == [], "an app that does not answer yields an empty menu, not a stall: %r" % payload)


def main():
    if not os.path.exists(DAEMON):
        sys.exit("build the daemon first: zig build")

    # Only one process per bus can own com.canonical.AppMenu.Registrar, and on a
    # live KOOMPI session that is the running daemon. Re-run ourselves on a
    # private bus so the tests never depend on, or disturb, the real session.
    if not os.environ.get("KOOMPI_GLOBAL_MENU_TEST_BUS"):
        env = dict(os.environ, KOOMPI_GLOBAL_MENU_TEST_BUS="1")
        sys.exit(subprocess.call(["dbus-run-session", "--", sys.executable, __file__], env=env))

    with tempfile.TemporaryDirectory() as tmp:
        log = os.path.join(tmp, "activations.log")
        open(log, "w").close()
        daemon = Daemon()
        try:
            test_gtk(daemon, log)
            test_dbusmenu(daemon, log)
            test_no_menu(daemon)
        finally:
            daemon.stop()

    if failures:
        print("\n%d check(s) failed" % len(failures))
        sys.exit(1)
    print("\nall checks passed")


if __name__ == "__main__":
    main()
