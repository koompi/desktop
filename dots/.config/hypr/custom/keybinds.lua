hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- Kiri voice dictation on the AI/Copilot key (Super+Shift+F23, code:201).
-- Plain AI key = English; add Alt for Khmer. Press once to start, again to
-- stop. The "Kiri: ..." descriptions group these in the cheatsheet.
hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice --lang km"), { description = "Kiri: Khmer dictation (AI key + Alt)" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice"), { description = "Kiri: Voice transcription (AI key)" })
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("$HOME/.local/bin/kiri voice --lang km"), { description = "Kiri: Khmer dictation (Super+Shift+K)" })
hl.bind("SUPER + Escape", hl.dsp.exec_cmd("$HOME/.local/bin/kiri cancel"), { description = "Kiri: Cancel dictation (Super+Esc)" })
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("$HOME/.local/bin/kiri-gui"), { description = "Kiri: Settings" })
