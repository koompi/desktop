#!/usr/bin/env python3
"""A com.canonical.dbusmenu exporter that registers with the AppMenu registrar.

This stands in for a Qt/KDE application, or a GTK application running under
appmenu-gtk-module: it registers its window with whatever owns
com.canonical.AppMenu.Registrar and answers GetLayout / Event / AboutToShow.

The "Tools" submenu is deliberately empty until AboutToShow arrives, which is
how Qt menus behave, so the test can check that opening a menu populates it.

argv[1] is the activation log, argv[2] the window id to register.
"""

import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS_NAME = "org.koompi.test.QtApp"
MENU_PATH = "/MenuBar"

INTROSPECTION = """
<node>
  <interface name="com.canonical.dbusmenu">
    <property name="Version" type="u" access="read"/>
    <property name="Status" type="s" access="read"/>
    <method name="GetLayout">
      <arg type="i" name="parentId" direction="in"/>
      <arg type="i" name="recursionDepth" direction="in"/>
      <arg type="as" name="propertyNames" direction="in"/>
      <arg type="u" name="revision" direction="out"/>
      <arg type="(ia{sv}av)" name="layout" direction="out"/>
    </method>
    <method name="AboutToShow">
      <arg type="i" name="id" direction="in"/>
      <arg type="b" name="needUpdate" direction="out"/>
    </method>
    <method name="Event">
      <arg type="i" name="id" direction="in"/>
      <arg type="s" name="eventId" direction="in"/>
      <arg type="v" name="data" direction="in"/>
      <arg type="u" name="timestamp" direction="in"/>
    </method>
  </interface>
</node>
"""


class Node:
    def __init__(self, node_id, props, children=()):
        self.id = node_id
        self.props = props
        self.children = list(children)

    def to_variant(self):
        props = GLib.VariantBuilder(GLib.VariantType("a{sv}"))
        for key, value in self.props.items():
            props.add_value(GLib.Variant("{sv}", (key, value)))
        kids = GLib.VariantBuilder(GLib.VariantType("av"))
        for child in self.children:
            kids.add_value(GLib.Variant.new_variant(child.to_variant()))
        return GLib.Variant.new_tuple(GLib.Variant("i", self.id), props.end(), kids.end())


def label(text):
    return {"label": GLib.Variant("s", text)}


class App:
    def __init__(self, log):
        self.log = log
        self.tools_populated = False
        self.root = Node(
            0,
            {},
            [
                Node(
                    1,
                    dict(label("&File"), **{"children-display": GLib.Variant("s", "submenu")}),
                    [
                        Node(2, label("New")),
                        Node(3, {"type": GLib.Variant("s", "separator")}),
                        Node(4, dict(label("Quit"), enabled=GLib.Variant("b", False))),
                    ],
                ),
                Node(
                    5,
                    dict(label("&Tools"), **{"children-display": GLib.Variant("s", "submenu")}),
                    [],
                ),
                Node(
                    6,
                    label("Hidden"),
                ),
            ],
        )
        self.root.children[2].props["visible"] = GLib.Variant("b", False)

    def find(self, node, node_id):
        if node.id == node_id:
            return node
        for child in node.children:
            found = self.find(child, node_id)
            if found is not None:
                return found
        return None

    def handle(self, conn, sender, path, iface, method, params, invocation):
        if method == "GetLayout":
            parent_id = params[0]
            node = self.find(self.root, parent_id) or self.root
            layout = GLib.Variant.new_tuple(GLib.Variant("u", 1), node.to_variant())
            invocation.return_value(layout)
        elif method == "AboutToShow":
            node_id = params[0]
            updated = False
            if node_id == 5 and not self.tools_populated:
                self.tools_populated = True
                self.root.children[1].children = [
                    Node(7, dict(label("Preferences"), **{
                        "toggle-type": GLib.Variant("s", "checkmark"),
                        "toggle-state": GLib.Variant("i", 1),
                    })),
                ]
                updated = True
            self.log.write("abouttoshow %d\n" % node_id)
            invocation.return_value(GLib.Variant("(b)", (updated,)))
        elif method == "Event":
            self.log.write("event %d %s\n" % (params[0], params[1]))
            invocation.return_value(None)
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


def main():
    log = open(sys.argv[1], "a", buffering=1)
    window_id = int(sys.argv[2])

    app = App(log)
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    node_info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION)
    conn.register_object(MENU_PATH, node_info.interfaces[0], app.handle, None, None)

    def owned(*_args):
        conn.call_sync(
            "com.canonical.AppMenu.Registrar",
            "/com/canonical/AppMenu/Registrar",
            "com.canonical.AppMenu.Registrar",
            "RegisterWindow",
            GLib.Variant("(uo)", (window_id, MENU_PATH)),
            None,
            Gio.DBusCallFlags.NONE,
            -1,
            None,
        )
        print("READY", flush=True)

    Gio.bus_own_name_on_connection(
        conn, BUS_NAME, Gio.BusNameOwnerFlags.NONE, owned, lambda *a: sys.exit("name lost")
    )
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
