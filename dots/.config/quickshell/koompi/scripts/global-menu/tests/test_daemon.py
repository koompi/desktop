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
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# Two implementations answer this protocol, so the suite is the conformance
# gate for both. GLOBAL_MENU_DAEMON points it at the one under test.
DAEMON = os.environ.get(
    "GLOBAL_MENU_DAEMON",
    os.path.join(HERE, "..", "zig-out", "bin", "global-menu-daemon"),
)

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
        self.generation = 0
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

    def send_item(self, verb, item_id, generation=None):
        """Drives an item the way the shell does: ids are only valid inside the
        payload they arrived in, so the generation goes back with them."""
        gen = self.generation if generation is None else generation
        self.send("%s %d %d" % (verb, item_id, gen))

    def read(self, timeout=10.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if line.strip():
                payload = json.loads(line)
                if "gen" in payload:
                    self.generation = payload["gen"]
                return payload
        raise AssertionError("daemon produced no payload")

    def stop(self):
        try:
            self.proc.stdin.close()
        except OSError:
            pass  # test_restart_recovery kills the daemon on purpose
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

        daemon.send_item("activate", find(items, "Quit")["id"])
        daemon.send_item("activate", find(items, "List")["id"])
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

        daemon.send_item("open", tools["id"])
        patch = daemon.read()
        check(patch.get("patch") == tools["id"], "opening it produces a patch for that item")
        check(
            patch.get("gen") == payload.get("gen"),
            "a patch stays inside the payload's id space rather than opening a new one",
        )
        check(
            [i["label"] for i in patch["items"]] == ["Preferences"],
            "the patch carries the entries the app built on AboutToShow",
        )
        pref = patch["items"][0]
        check(pref["toggle"] and pref["checked"], "toggle state survives the patch")
        check(pref.get("sub") is None, "a patched leaf is not marked as a submenu")

        daemon.send_item("activate", pref["id"])
        content = wait_for(log, lambda c: "event 7 clicked" in c)
        check("event 7 clicked" in content, "clicking a patched entry sends Event(clicked)")

        daemon.send_item("activate", find(items, "New")["id"])
        content = wait_for(log, lambda c: "event 2 clicked" in c)
        check("event 2 clicked" in content, "clicking a top-level entry sends Event(clicked)")

        test_stale_generation(daemon, log, items)
    finally:
        app.terminate()
        app.wait(timeout=5)


def test_stale_generation(daemon, log, items):
    """A click the user made just before focus moved must not land on the menu
    that replaced it. Ids are per-payload and reused, so "activate 2" against
    the old File menu would otherwise invoke whatever is now item 2."""
    print("commands queued against a menu that has been replaced")
    new_id = find(items, "New")["id"]
    stale_gen = daemon.generation

    # Re-publish. Same application, but the table is rebuilt from scratch, so
    # every id the shell was holding now belongs to the previous generation.
    daemon.send("dbusmenu org.koompi.test.QtApp /MenuBar")
    daemon.read()
    check(daemon.generation != stale_gen, "a replacement payload carries a new generation")

    with open(log) as fh:
        before = fh.read().count("event 2 clicked")

    # The stale click first, then a current one. Commands are processed in
    # order, so once the second has landed the first has had its chance.
    daemon.send_item("activate", new_id, generation=stale_gen)
    daemon.send_item("activate", new_id)
    wait_for(log, lambda c: c.count("event 2 clicked") > before)

    with open(log) as fh:
        after = fh.read().count("event 2 clicked")
    check(
        after == before + 1,
        "the stale click is dropped and only the current one reaches the app "
        "(%d click(s) landed, expected 1)" % (after - before),
    )

    # An unversioned command cannot be checked at all, so it is refused too.
    daemon.send("activate %d" % new_id)
    daemon.send_item("activate", new_id)
    wait_for(log, lambda c: c.count("event 2 clicked") > after)
    with open(log) as fh:
        final = fh.read().count("event 2 clicked")
    check(
        final == after + 1,
        "a command naming no generation is refused "
        "(%d click(s) landed, expected 1)" % (final - after),
    )


def test_patch_names_the_generation_it_was_asked_for(daemon, log):
    """A patch splices children into the payload the shell is holding, keyed by
    an id from that payload. If it ever came back stamped with a generation its
    children do not belong to, the shell's own `payload.gen !== generation`
    check would wave it through and hang one application's submenu off another
    application's item id.

    The application sits on AboutToShow for a second and a half, so the whole
    open request is in flight while a replacement payload is already queued
    behind it. That is the window the guard has to survive."""
    print("a patch issued while a replacement payload is queued")
    app = start_mock("mock_dbusmenu_app.py", log, 4248, "org.koompi.test.SlowApp", 1.5)
    try:
        daemon.send("dbusmenu org.koompi.test.SlowApp /MenuBar")
        payload = daemon.read()
        asked_gen = payload["gen"]
        tools = find(payload["items"], "Tools")

        daemon.send_item("open", tools["id"], generation=asked_gen)
        time.sleep(0.3)  # the daemon is inside AboutToShow by now
        daemon.send("dbusmenu org.koompi.test.SlowApp /MenuBar")

        patch = daemon.read()
        check(patch.get("patch") == tools["id"], "the patch answers the open: %r" % patch)
        check(
            patch.get("gen") == asked_gen,
            "the patch names the generation the open was issued under, not the "
            "one current when it was answered (%r, asked under %r)"
            % (patch.get("gen"), asked_gen),
        )

        replacement = daemon.read()
        check(
            replacement.get("patch") is None and replacement.get("gen") != asked_gen,
            "the queued replacement is only published afterwards, in a new id "
            "space: %r" % {k: v for k, v in replacement.items() if k != "items"},
        )

        # And an open against the payload that has just been replaced answers
        # nothing at all, so no children can arrive for a dead id space.
        daemon.send_item("open", tools["id"], generation=asked_gen)
        daemon.send("dbusmenu org.koompi.test.SlowApp /MenuBar")
        after = daemon.read()
        check(
            after.get("patch") is None,
            "an open naming the replaced generation produces no patch: %r" % after,
        )
    finally:
        app.terminate()
        app.wait(timeout=5)


def test_no_menu(daemon):
    print("applications with no exported menu")
    daemon.send("dbusmenu org.koompi.test.Nothing /MenuBar")
    payload = daemon.read()
    check(payload["items"] == [], "an app that does not answer yields an empty menu, not a stall: %r" % payload)


def test_register_window_answers_promptly(daemon):
    print("RegisterWindow answers without stalling the application")
    # Qt's QDBusMenuBar makes this call synchronously from QMenuBar's
    # constructor, so every millisecond spent here is a millisecond the
    # window is not on screen. The registrar looks up the caller's pid on the
    # same connection it is answering on; if that lookup blocks the executor,
    # its reply is never read and the call sits on the 3 s method timeout.
    started = time.monotonic()
    gdbus("com.canonical.AppMenu.Registrar", "RegisterWindow", 4300, "/MenuBar/1")
    elapsed = time.monotonic() - started
    check(elapsed < 1.0, "RegisterWindow returned in %.3fs" % elapsed)
    gdbus("com.canonical.AppMenu.Registrar", "UnregisterWindow", 4300)


def gdbus(dest, method, *args):
    return subprocess.run(
        [
            "gdbus", "call", "--session",
            "--dest", dest,
            "--object-path", "/com/canonical/AppMenu/Registrar",
            "--method", "com.canonical.AppMenu.Registrar." + method,
        ] + [str(a) for a in args],
        capture_output=True,
        text=True,
    ).stdout.strip()


def bus_call(method, *args):
    return subprocess.run(
        [
            "gdbus", "call", "--session",
            "--dest", "org.freedesktop.DBus",
            "--object-path", "/org/freedesktop/DBus",
            "--method", "org.freedesktop.DBus." + method,
        ] + [str(a) for a in args],
        capture_output=True,
        text=True,
    ).stdout.strip()


def get_menus(dest="com.canonical.AppMenu.Registrar"):
    return gdbus(dest, "GetMenus")


def menu_windows(dest="com.canonical.AppMenu.Registrar"):
    """The window ids the registrar is serving, one per registration, so a
    duplicated entry shows up as a repeated id rather than being collapsed.

    gdbus prints the `uint32` annotation on the first row of the array only, so
    matching on it finds one entry however many there are - which is exactly the
    duplicate this is here to catch."""
    return re.findall(r"\((?:uint32 )?(\d+), '", get_menus(dest))


def registrar_owner():
    """Unique name of whoever currently owns the well-known name."""
    return bus_call("GetNameOwner", "com.canonical.AppMenu.Registrar")


def unique_name_of(pid):
    """The bus name of a daemon we started, so a test can address one daemon
    directly instead of whichever one happens to own the registrar name."""
    for name in re.findall(r"'(:[0-9.]+)'", bus_call("ListNames")):
        if re.search(r"\b%d\b" % pid, bus_call("GetConnectionUnixProcessID", name)):
            return name
    raise AssertionError("no bus name for pid %d" % pid)


def mirror_path():
    return os.path.join(os.environ["XDG_RUNTIME_DIR"], "koompi-global-menu.registry")


def mirror_windows():
    """Window ids in the on-disk mirror, which is what the next daemon recovers."""
    try:
        with open(mirror_path()) as fh:
            return [line.split("\t")[0] for line in fh.read().splitlines() if line]
    except FileNotFoundError:
        return []


def wait_until(predicate, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def test_restart_recovery(daemon):
    """An application registers once, when it first sees somebody own the name.
    If a daemon restart lost the table, every menu would stay missing until the
    user restarted the application itself, which is not an acceptable ask."""
    print("recovering registrations across a daemon restart")
    app = start_mock("mock_dbusmenu_app.py", os.devnull, 4243)
    try:
        before = get_menus()
        check("4243" in before, "the application is registered before the restart: %s" % before)

        # Kill the daemon the way a crash or a shell reload would, and bring up
        # a replacement against the same bus. The application is never touched.
        daemon.proc.kill()
        daemon.proc.wait(timeout=5)
        replacement = Daemon()
        try:
            deadline = time.time() + 5.0
            after = ""
            while time.time() < deadline:
                after = get_menus()
                if "4243" in after:
                    break
                time.sleep(0.1)
            check(
                "4243" in after,
                "the registration is recovered without restarting the app: %s" % after,
            )
            check(
                app.poll() is None,
                "the application really was left running the whole time",
            )
        finally:
            replacement.stop()
    finally:
        app.terminate()
        app.wait(timeout=5)


def test_stale_registration_dropped():
    """The mirrored table must not resurrect an application that has exited."""
    print("registrations of applications that exited")
    # The daemon first: the application registers as soon as it starts, so with
    # nobody owning the registrar name there is nothing for it to register with.
    daemon = Daemon()
    app = start_mock("mock_dbusmenu_app.py", os.devnull, 4244)
    try:
        check("4244" in get_menus(), "registered while the app was alive")
    finally:
        # In this order: with the daemon still up it would see the application
        # go and clean the mirror itself, which is not what is under test here.
        daemon.stop()
    app.terminate()
    app.wait(timeout=5)

    revived = Daemon()
    try:
        deadline = time.time() + 3.0
        while time.time() < deadline and "4244" in get_menus():
            time.sleep(0.1)
        check(
            "4244" not in get_menus(),
            "a dead application is dropped rather than restored: %s" % get_menus(),
        )
    finally:
        revived.stop()


def test_reacquired_name_does_not_duplicate():
    """The name is asked for with ALLOW_REPLACEMENT, so a second daemon can take
    it and the bus hands it back when that one exits. Every acquisition restores
    the mirror, so restoring twice must not leave two entries for one window: the
    bar would show that application's menu twice, and forWindow would answer from
    whichever copy happened to come first."""
    print("the registrar name being taken away and handed back")
    first = Daemon()
    app = None
    try:
        app = start_mock("mock_dbusmenu_app.py", os.devnull, 4245)
        held = registrar_owner()
        check(menu_windows() == ["4245"], "one entry to begin with: %s" % menu_windows())

        # A restarted daemon takes the name with REPLACE. The first one stays
        # queued behind it rather than giving up, which is what makes the
        # hand-back happen at all.
        replacement = Daemon()
        check(
            wait_until(lambda: registrar_owner() not in ("", held)),
            "the replacement takes the name from the first daemon",
        )
        replacement.stop()
        check(
            wait_until(lambda: registrar_owner() == held),
            "the name comes back to the first daemon when the replacement exits",
        )

        wait_until(lambda: menu_windows() == ["4245"])
        check(
            menu_windows() == ["4245"],
            "the recovered registration is not duplicated: %s" % menu_windows(),
        )
        check(mirror_windows() == ["4245"], "nor duplicated in the mirror: %s" % mirror_windows())
    finally:
        if app is not None:
            app.terminate()
            app.wait(timeout=5)
        first.stop()


def test_displaced_daemon_does_not_write_the_mirror():
    """A daemon that lost the name still holds a table, and still sees the bus
    signals that change it. If it keeps mirroring that table it overwrites the
    real owner's, and the next restart recovers the wrong set of menus."""
    print("a daemon that has lost the name writing the mirror")
    displaced = Daemon()
    apps = []
    owner = None
    try:
        apps.append(start_mock("mock_dbusmenu_app.py", os.devnull, 4246))
        held = registrar_owner()
        check(mirror_windows() == ["4246"], "the first daemon mirrored its table")

        owner = Daemon()
        check(
            wait_until(lambda: registrar_owner() not in ("", held)),
            "the second daemon takes the name",
        )
        # Registered while the second daemon owns the name, so only it knows.
        apps.append(start_mock("mock_dbusmenu_app.py", os.devnull, 4247, "org.koompi.test.QtApp2"))
        check(
            wait_until(lambda: sorted(mirror_windows()) == ["4246", "4247"]),
            "the owner mirrors both registrations: %s" % mirror_windows(),
        )

        # Make the displaced daemon change its own table, addressing it by unique
        # name so the request cannot reach the owner instead.
        stale = unique_name_of(displaced.proc.pid)
        gdbus(stale, "UnregisterWindow", 4246)
        check(
            wait_until(lambda: menu_windows(stale) == []),
            "the displaced daemon did drop it from its own table: %s" % menu_windows(stale),
        )

        check(
            sorted(mirror_windows()) == ["4246", "4247"],
            "the mirror still describes the owner's table, not the displaced one: %s"
            % mirror_windows(),
        )
        check(
            sorted(menu_windows()) == ["4246", "4247"],
            "and the owner still serves both: %s" % menu_windows(),
        )
        check(
            not os.path.exists(mirror_path() + ".new"),
            "the mirror is written through a temporary that gets renamed, not left behind",
        )
    finally:
        if owner is not None:
            owner.stop()
        displaced.stop()
        for app in apps:
            app.terminate()
            app.wait(timeout=5)


def main():
    if not os.path.exists(DAEMON):
        sys.exit("build the daemon first: zig build")

    # Only one process per bus can own com.canonical.AppMenu.Registrar, and on a
    # live KOOMPI session that is the running daemon. Re-run ourselves on a
    # private bus so the tests never depend on, or disturb, the real session.
    if not os.environ.get("KOOMPI_GLOBAL_MENU_TEST_BUS"):
        # A private bus AND a private XDG_RUNTIME_DIR. The registrar mirrors its
        # table to $XDG_RUNTIME_DIR/koompi-global-menu.registry, so without this
        # the tests read the live daemon's mirror, find none of its unique names
        # on our bus, and write the emptied table back over it.
        with tempfile.TemporaryDirectory() as runtime:
            env = dict(
                os.environ,
                KOOMPI_GLOBAL_MENU_TEST_BUS="1",
                XDG_RUNTIME_DIR=runtime,
            )
            sys.exit(subprocess.call(["dbus-run-session", "--", sys.executable, __file__], env=env))

    with tempfile.TemporaryDirectory() as tmp:
        log = os.path.join(tmp, "activations.log")
        open(log, "w").close()
        daemon = Daemon()
        try:
            test_gtk(daemon, log)
            test_dbusmenu(daemon, log)
            test_patch_names_the_generation_it_was_asked_for(daemon, log)
            test_no_menu(daemon)
            test_register_window_answers_promptly(daemon)
            # Kills `daemon` and runs its own replacement, so nothing may use the
            # shared one after this.
            test_restart_recovery(daemon)
        finally:
            daemon.stop()
        test_stale_registration_dropped()
        test_reacquired_name_does_not_duplicate()
        test_displaced_daemon_does_not_write_the_mirror()

    if failures:
        print("\n%d check(s) failed" % len(failures))
        sys.exit(1)
    print("\nall checks passed")


if __name__ == "__main__":
    main()
