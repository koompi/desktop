#!/usr/bin/env python3
"""A GtkApplication-shaped menu exporter, without the GUI.

GLib exports org.gtk.Menus and org.gtk.Actions for us, so this is the same wire
format a real GTK application produces: a menubar built from sections, a nested
submenu, a disabled action, a checkbox and a radio group.

Every activation is appended to the log file given as argv[1], one per line, so
the test can assert that a click in the bar reached the application.
"""

import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "org.koompi.test.GtkApp"
APP_PATH = "/org/koompi/test/GtkApp"
MENUBAR_PATH = APP_PATH + "/menus/menubar"
WINDOW_PATH = APP_PATH + "/window/1"


def build_menubar():
    menubar = Gio.Menu()

    file_menu = Gio.Menu()
    first = Gio.Menu()
    first.append("_New Window", "app.new-window")
    first.append("_Open...", "win.open")
    file_menu.append_section(None, first)
    second = Gio.Menu()
    second.append("_Print", "win.print")  # action is disabled
    second.append("_Quit", "app.quit")
    file_menu.append_section(None, second)
    menubar.append_submenu("_File", file_menu)

    view_menu = Gio.Menu()
    view_menu.append("Show _Sidebar", "win.sidebar")  # boolean state
    for label, value in (("_List", "list"), ("_Grid", "grid")):
        item = Gio.MenuItem.new(label, None)
        item.set_action_and_target_value("win.layout", GLib.Variant.new_string(value))
        view_menu.append_item(item)
    deeper = Gio.Menu()
    deeper.append("_Deep Item", "win.deep")
    view_menu.append_submenu("_More", deeper)
    menubar.append_submenu("_View", view_menu)

    return menubar


def main():
    log_path = sys.argv[1]
    log = open(log_path, "a", buffering=1)

    def record(action, parameter):
        log.write("%s %s\n" % (action.get_name(), parameter.print_(False) if parameter else "-"))

    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    app_actions = Gio.SimpleActionGroup()
    for name in ("new-window", "quit"):
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", record)
        app_actions.add_action(action)

    win_actions = Gio.SimpleActionGroup()
    for name in ("open", "deep"):
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", record)
        win_actions.add_action(action)

    disabled = Gio.SimpleAction.new("print", None)
    disabled.set_enabled(False)
    disabled.connect("activate", record)
    win_actions.add_action(disabled)

    sidebar = Gio.SimpleAction.new_stateful("sidebar", None, GLib.Variant.new_boolean(True))
    sidebar.connect("activate", record)
    win_actions.add_action(sidebar)

    layout = Gio.SimpleAction.new_stateful(
        "layout", GLib.VariantType.new("s"), GLib.Variant.new_string("grid")
    )
    layout.connect("activate", record)
    win_actions.add_action(layout)

    conn.export_menu_model(MENUBAR_PATH, build_menubar())
    conn.export_action_group(APP_PATH, app_actions)
    conn.export_action_group(WINDOW_PATH, win_actions)

    Gio.bus_own_name_on_connection(
        conn,
        BUS_NAME,
        Gio.BusNameOwnerFlags.NONE,
        lambda *a: print("READY", flush=True),
        lambda *a: sys.exit("could not own %s" % BUS_NAME),
    )
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
