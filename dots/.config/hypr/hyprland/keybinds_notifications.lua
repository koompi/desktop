-- Notification chords (OMARCHY-AUDIT O12), one file of their own because
-- hyprland/keybinds.lua sits at its row in tests/file-length-allow.txt (447
-- lines) and may not grow. hyprland.lua requires this right after keybinds.lua,
-- so hl.bind here is already the wrapper that arms the Super-release interrupt.
--
-- The chords are omarchy's (default/hypr/bindings/utilities.lua:24-28),
-- unchanged: nothing in keybinds.lua or custom/keybinds.lua binds Comma.
-- Omarchy's fifth, Super+Ctrl+Comma for silencing, is `koompi toggle silent`
-- and gets no chord here. Everything runs in the shell over IPC
-- (services/Notifications.qml, target "notifications"); there is no fallback
-- when the shell is down, because there is no toast to act on then either.
local notifications = "qs -c $qsConfig ipc --any-display call notifications"

hl.bind("SUPER + Comma", hl.dsp.exec_cmd(notifications .. " dismissOne"),
    { description = "Shell: Notifications - dismiss the newest toast" })
hl.bind("SUPER + SHIFT + Comma", hl.dsp.exec_cmd(notifications .. " dismissAll"),
    { description = "Shell: Notifications - dismiss all toasts" })
hl.bind("SUPER + ALT + Comma", hl.dsp.exec_cmd(notifications .. " invokeLast"),
    { description = "Shell: Notifications - open the newest toast (its default action)" })
hl.bind("SUPER + SHIFT + ALT + Comma", hl.dsp.exec_cmd(notifications .. " showHistory"),
    { description = "Shell: Notifications - show history (right sidebar)" })
