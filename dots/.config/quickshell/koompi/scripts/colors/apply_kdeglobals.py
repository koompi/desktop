#!/usr/bin/env python3
"""Merge a KColorScheme .colors file into ~/.config/kdeglobals.

Replaces plasma-apply-colorscheme (M7 Qt unwind): KDE Frameworks apps read
kdeglobals directly, so merging the matugen-rendered scheme keeps them themed
without plasma-workspace. Sections merged: [Colors:*], [ColorEffects:*], [WM].
Also sets [General] ColorScheme and, with --icon-theme, [Icons] Theme.

ponytail: no DBus change notification, running KDE apps recolor on next
launch. Wire KConfigWatcher signalling if live recolor ever matters.
"""
import sys, os, tempfile

def parse(path):
    """File -> ordered list of [section_name_or_None, [lines]]."""
    blocks, cur = [], [None, []]
    with open(path, encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith("["):
                blocks.append(cur)
                cur = [stripped[1:-1] if stripped.endswith("]") else stripped[1:], []]
            else:
                cur[1].append(line.rstrip("\n"))
        blocks.append(cur)
    return blocks

def body(lines):
    return [l for l in lines if l.strip() and not l.strip().startswith("#")]

def main():
    if len(sys.argv) < 2:
        sys.exit("usage: apply_kdeglobals.py <scheme.colors> [--icon-theme <name>]")
    scheme_path = sys.argv[1]
    icon_theme = None
    if "--icon-theme" in sys.argv:
        icon_theme = sys.argv[sys.argv.index("--icon-theme") + 1]

    kdeglobals = os.path.join(
        os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "kdeglobals")

    scheme = {name: lines for name, lines in parse(scheme_path) if name}
    merged = {n: b for n, b in scheme.items()
              if n.startswith("Colors:") or n.startswith("ColorEffects:") or n == "WM"}
    scheme_name = "KoompiMaterial"
    for l in scheme.get("General", []):
        if l.startswith("ColorScheme="):
            scheme_name = l.split("=", 1)[1]

    target = parse(kdeglobals) if os.path.exists(kdeglobals) else [[None, []]]
    seen = set()
    for block in target:
        name = block[0]
        if name in merged:
            block[1] = body(merged[name])
            seen.add(name)
        elif name == "General":
            block[1] = [("ColorScheme=" + scheme_name) if l.startswith("ColorScheme=") else l
                        for l in block[1]]
            if not any(l.startswith("ColorScheme=") for l in block[1]):
                block[1].append("ColorScheme=" + scheme_name)
        elif name == "Icons" and icon_theme:
            block[1] = [("Theme=" + icon_theme) if l.startswith("Theme=") else l
                        for l in block[1]]
    for name in sorted(merged):
        if name not in seen:
            target.append([name, body(merged[name])])
    if not any(b[0] == "General" for b in target):
        target.append(["General", ["ColorScheme=" + scheme_name]])
    if icon_theme and not any(b[0] == "Icons" for b in target):
        target.append(["Icons", ["Theme=" + icon_theme]])

    out = []
    for name, lines in target:
        if name is not None:
            if out and out[-1] != "":
                out.append("")
            out.append("[" + name + "]")
        out.extend(lines)
    text = "\n".join(out).rstrip("\n") + "\n"

    # Validate before replacing: round-trips and still carries the scheme.
    assert "[Colors:Window]" in text and "ColorScheme=" + scheme_name in text
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(kdeglobals))
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, kdeglobals)

if __name__ == "__main__":
    main()
