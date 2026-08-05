local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Touch is dropped here on purpose: wezterm's Wayland backend never calls
-- wl_seat.get_touch, and the X11 backend that did give pointer-emulated touch
-- put every keystroke through XWayland. Typing latency won over the touchscreen.

-- Kitty keyboard protocol is opt-in per application. zsh never asks for it, so
-- it kept getting the legacy ^[[3~ for Delete and behaved; TUIs that DO ask for
-- it (Claude Code) got the CSI-u encoding instead and fell through to backspace
-- handling, so Delete deleted leftwards. Off until a TUI actually needs it.
config.enable_kitty_keyboard = false
config.window_background_opacity = 0.80
config.text_background_opacity = 1.0
config.window_decorations = 'NONE'
config.font_size = 11.5

config.colors = {
  foreground = '#00ff66',
  background = '#020403',
  cursor_bg = '#00ff66',
  cursor_fg = '#020403',
  cursor_border = '#00ff66',
  selection_fg = '#020403',
  selection_bg = '#39ff88',
  scrollbar_thumb = '#0f5f2f',
  split = '#0f5f2f',
  ansi = {
    -- Keep ANSI black readable on the dark background; some tools color
    -- lockfiles (e.g. bun.lock) as black/dim.
    '#4f7f5f',
    '#ff4d4d',
    '#00ff66',
    '#ffd75f',
    '#5fafff',
    '#ff5fff',
    '#5fffff',
    '#d7ffd7',
  },
  brights = {
    '#7fbf8f',
    '#ff6b6b',
    '#39ff88',
    '#ffe680',
    '#80c7ff',
    '#ff80ff',
    '#80ffff',
    '#ffffff',
  },
  tab_bar = {
    background = '#020403',
    active_tab = {
      bg_color = '#0b2f18',
      fg_color = '#39ff88',
      intensity = 'Bold',
    },
    inactive_tab = {
      bg_color = '#061009',
      fg_color = '#3f8f5f',
    },
    inactive_tab_hover = {
      bg_color = '#0f3f22',
      fg_color = '#8cffb5',
    },
    new_tab = {
      bg_color = '#061009',
      fg_color = '#3f8f5f',
    },
    new_tab_hover = {
      bg_color = '#0f3f22',
      fg_color = '#8cffb5',
    },
  },
}

return config
