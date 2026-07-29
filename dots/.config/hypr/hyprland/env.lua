local home_dir = os.getenv("HOME")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
local flatpak_data_dirs = home_dir .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
-- Reloads re-run this file; without the guard the flatpak paths get prepended
-- again every time and the value grows without bound.
if not string.find(xdg_data_dirs_old, "/var/lib/flatpak/exports/share", 1, true) then
    hl.env("XDG_DATA_DIRS", flatpak_data_dirs .. ":" .. xdg_data_dirs_old)
end

-- Global menu: GTK apps export their menubar over DBus instead of drawing it
hl.env("GTK_MODULES", "appmenu-gtk-module")

-- File dialogs: route GTK3/GTK4/Electron native choosers through the portal so
-- every app gets the same floating centered picker (portal class rules in rules.lua)
hl.env("GTK_USE_PORTAL", "1")

-- KDE's crash handler assumes a Plasma session; outside one it can only park
-- a dead "closed unexpectedly" icon in the tray. Let crashes just exit.
hl.env("KDE_DEBUG", "1")

-- Themes
-- xcb, not wayland: Qt exports its menubar over D-Bus only on X11, so a native
-- Wayland Qt app leaves the global menu empty. Anything that must stay on
-- Wayland (the shell itself) overrides this at its own launch.
hl.env("QT_QPA_PLATFORM", "xcb")
-- qt6ct, not kde: Qt apps read the matugen-rendered qt6ct palette instead of
-- loading plasma-integration (M5/M7 Qt unwind).
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- Cursor
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")
