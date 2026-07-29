-- KOOMPI's wezterm defaults. wezterm is the first entry in `terminal` in
-- hyprland/variables.lua, so this is the terminal most KOOMPI users get.
--
-- This file is an override slot: `./setup install` writes it only when you do
-- not already have one, and never touches it again. Edit it freely.
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- wezterm's Wayland backend never calls wl_seat.get_touch, so touchscreen input
-- is dropped entirely. XWayland exposes the touchscreen as a slave pointer
-- device, so the X11 backend gets pointer-emulated touch instead. Drop this
-- line on a machine with no touchscreen and wezterm runs natively on Wayland.
config.enable_wayland = false

-- As an X11 client wezterm picks its own pointer via libXcursor instead of
-- inheriting the one `hyprctl setcursor` hands to Wayland clients, so it follows
-- whatever XCURSOR_THEME was in the session env when it started. Pin it to the
-- same theme hyprland/env.lua, execs.lua and the GTK settings use, or you get
-- two different pointers in one session.
config.xcursor_theme = 'Bibata-Modern-Classic'
config.xcursor_size = 24

-- The kitty keyboard protocol is opt-in per application, which is what makes
-- this subtle: shells never ask for it and keep getting the legacy ^[[3~ for
-- Delete, so Delete works, while a TUI that DOES ask for it (Claude Code) gets
-- the CSI-u encoding, falls through to backspace handling, and deletes
-- leftwards instead. Off until a TUI you use actually needs it.
config.enable_kitty_keyboard = false

config.window_background_opacity = 0.90
config.text_background_opacity = 1.0
-- The bar and the window rules own the frame; wezterm drawing its own title bar
-- on top of that just costs rows.
config.window_decorations = 'NONE'
config.font_size = 11.5

return config
