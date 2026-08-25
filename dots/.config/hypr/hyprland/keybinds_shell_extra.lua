-- Shell chords that do not fit hyprland/keybinds.lua, which sits at its row in
-- tests/file-length-allow.txt (447 lines) and may not grow. hyprland.lua
-- requires this right after keybinds.lua, so hl.bind here is already the
-- wrapper that arms the Super-release interrupt.

-- Notifications (OMARCHY-AUDIT O12). The chords are omarchy's
-- (default/hypr/bindings/utilities.lua:24-28), unchanged: nothing in
-- keybinds.lua or custom/keybinds.lua binds Comma. Omarchy's fifth,
-- Super+Ctrl+Comma for silencing, is `koompi toggle silent` and gets no chord
-- here. Everything runs in the shell over IPC (services/Notifications.qml,
-- target "notifications"); there is no fallback when the shell is down,
-- because there is no toast to act on then either.
local notifications = "qs -c $qsConfig ipc --any-display call notifications"

hl.bind("SUPER + Comma", hl.dsp.exec_cmd(notifications .. " dismissOne"),
    { description = "Shell: Notifications - dismiss the newest toast" })
hl.bind("SUPER + SHIFT + Comma", hl.dsp.exec_cmd(notifications .. " dismissAll"),
    { description = "Shell: Notifications - dismiss all toasts" })
hl.bind("SUPER + ALT + Comma", hl.dsp.exec_cmd(notifications .. " invokeLast"),
    { description = "Shell: Notifications - open the newest toast (its default action)" })
hl.bind("SUPER + SHIFT + ALT + Comma", hl.dsp.exec_cmd(notifications .. " showHistory"),
    { description = "Shell: Notifications - show history (right sidebar)" })

-- Bar popups by keyboard (OMARCHY-AUDIT O34, omarchy's utilities.lua:109-115).
-- Super+Ctrl+N opens the Nth right-section popup counted left to right as the
-- bar renders them, pressing it again closes it, and Escape closes whichever
-- is open. The order is Bar.qml's (IpcHandler "bar") and docs/navigation.md
-- repeats it; 5-9 are bound so the range is one shape everywhere, and do
-- nothing until the bar grows a fifth popup.
local bar = "qs -c $qsConfig ipc --any-display call bar"
local popups = { "agent usage", "battery", "pomodoro", "clock" }
for n = 1, 9 do
    local what = popups[n] and (" (" .. popups[n] .. ")") or " (none yet)"
    hl.bind("SUPER + CTRL + " .. n, hl.dsp.exec_cmd(bar .. " popup " .. n),
        { description = "Shell: bar popup " .. n .. what })
    -- keycode twin for layouts whose number row types other characters, as keybinds.lua does
    hl.bind("SUPER + CTRL + code:" .. (n + 9), hl.dsp.exec_cmd(bar .. " popup " .. n)) -- # [hidden]
end
