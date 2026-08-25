require("hyprland.lib")
require("hyprland.variables")
if is_file_exists(HOME .. "/.config/hypr/custom/variables.lua") then
    require("custom.variables")
end

local qsScripts = "$HOME/.config/quickshell/$qsConfig/scripts"
local hyprScripts = "$HOME/.config/hypr/hyprland/scripts"
local appScratch = hyprScripts .. "/toggle_app_scratchpad.sh"
local qsIpcCall = "qs -c $qsConfig ipc --any-display call"
local qsIsAlive = qsIpcCall .. " TEST_ALIVE"
local volumeFeedback = "pw-play --volume=0.8 /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga >/dev/null 2>&1"
-- apps become their own app-*.scope in app.slice so oomd can kill one, not the session
local function app(id, cmd)
    return hl.dsp.exec_cmd("koompi-launch --id " .. id .. " " .. cmd)
end

-- hl.bind rejects `catchall`, so every Super chord carries the release interrupt
-- itself. Wrapper stays installed for the rest of the config.
local searchToggleReleaseInterrupt = hl.dsp.global("quickshell:searchToggleReleaseInterrupt")
local bindWithoutInterrupt = hl.bind
hl.bind = function(keys, dispatcher, opts)
    local keybind = bindWithoutInterrupt(keys, dispatcher, opts)
    local chord = keys:upper()
    -- SUPER_L/R arms the toggle and must not cancel it. Everything else cancels,
    -- mouse buttons and drags included.
    if chord:match("SUPER") and not chord:match("SUPER_[LR]") then
        bindWithoutInterrupt(keys, searchToggleReleaseInterrupt, { transparent = true })
    end
    return keybind
end

hl.bind("SUPER + SUPER_L", hl.dsp.global("quickshell:searchToggleRelease"), { description = "Shell: Toggle search" })
hl.bind("SUPER + SUPER_R", hl.dsp.global("quickshell:searchToggleRelease")) -- # [hidden] right-Super twin
hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd(qsIsAlive .. " || pkill fuzzel || fuzzel")) -- # [hidden] fallback
hl.bind("SUPER + SUPER_R", hl.dsp.exec_cmd(qsIsAlive .. " || pkill fuzzel || fuzzel")) -- # [hidden] fallback

hl.bind("SUPER_L", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true }) -- # [hidden]
hl.bind("SUPER_R", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true }) -- # [hidden]
hl.bind("SUPER_L", hl.dsp.global("quickshell:workspaceNumber"),
    { ignore_mods = true, transparent = true, release = true }) -- # [hidden]
hl.bind("SUPER_R", hl.dsp.global("quickshell:workspaceNumber"),
    { ignore_mods = true, transparent = true, release = true }) -- # [hidden]
hl.bind("SUPER + Tab", hl.dsp.global("quickshell:overviewWorkspacesToggle"), { description = "Shell: Toggle overview" })
hl.bind("SUPER + V", hl.dsp.global("quickshell:overviewClipboardToggle"), { description = "Utilities: Clipboard history >> clipboard" })
hl.bind("SUPER + Period", hl.dsp.global("quickshell:overviewEmojiToggle"), { description = "Utilities: Emoji >> clipboard" })
hl.bind("SUPER + A", hl.dsp.global("quickshell:sidebarLeftToggle"), { description = "Shell: Toggle left sidebar" })
hl.bind("SUPER + ALT + A", hl.dsp.global("quickshell:sidebarLeftToggleDetach"), { description = "Shell: Detach left sidebar" })
-- The full window grabs the keyboard exclusively, so without a chord that closes
-- it the only way out is a button the surface has to be rendering for you to find.
hl.bind("SUPER + SHIFT + I", hl.dsp.global("quickshell:intelligenceToggle"),
    { description = "Shell: Toggle the full assistant window" })
hl.bind("SUPER + SHIFT + W", app("brave", "brave"), { description = "App: Brave browser" })
-- Okular has no plugin API, so enrolment cannot live in its menus; a global
-- bind is the nearest thing that works while a PDF is focused.
hl.bind("SUPER + SHIFT + E", app("koompi-signature", "koompi-signature capture"), { description = "App: Capture signature" })
hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd(appScratch .. " discord 'discord' koompi-launch --id discord discord"), { description = "App: Discord widget" })
hl.bind("SUPER + H", hl.dsp.exec_cmd(appScratch .. " whatsapp 'web.whatsapp.com' koompi-launch --id whatsapp " .. hyprScripts .. "/launch_whatsapp_web.sh"), { description = "App: WhatsApp widget" })
hl.bind("SUPER + Y", hl.dsp.exec_cmd(appScratch .. " telegram 'org\\.telegram\\.desktop|TelegramDesktop' koompi-launch --id telegram Telegram"), { description = "App: Telegram widget" })
hl.bind("SUPER + grave", hl.dsp.exec_cmd(appScratch .. " term 'term-scratch' 'koompi-launch --id term-scratch wezterm start --class term-scratch'"), { description = "App: Terminal widget" })
hl.bind("SUPER + backslash", hl.dsp.exec_cmd(appScratch .. " sysmon 'sysmon-scratch' koompi-launch --id sysmon " .. hyprScripts .. "/launch_sysmon.sh"), { description = "App: System monitor widget" })
-- SUPER + O is reserved for Quickwork and stays unbound until it exists.
-- The left sidebar keeps SUPER + A.
hl.bind("SUPER + N", hl.dsp.global("quickshell:sidebarRightToggle"), { description = "Shell: Toggle right sidebar" })
-- SUPER + ALT is one level deeper than SUPER + N: the panel opens straight onto
-- the page instead of onto its summary. Same chord again backs out.
hl.bind("SUPER + ALT + N", hl.dsp.global("quickshell:sidebarRightControls"), { description = "Shell: Right sidebar - all controls" })
hl.bind("SUPER + ALT + C", hl.dsp.global("quickshell:sidebarRightCalendar"), { description = "Shell: Right sidebar - calendar" })
hl.bind("SUPER + ALT + D", hl.dsp.global("quickshell:sidebarRightTodo"), { description = "Shell: Right sidebar - to-do list" })
hl.bind("SUPER + ALT + T", hl.dsp.global("quickshell:sidebarRightTimer"), { description = "Shell: Right sidebar - timer" })
hl.bind("SUPER + Slash", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Shell: Toggle cheatsheet" })
-- Beside the cheatsheet deliberately: the tour is what a new user needs before
-- the cheatsheet means anything, and the cheatsheet is what they reach for after.
hl.bind("SHIFT + SUPER + Slash", hl.dsp.global("quickshell:tourToggle"), { description = "Shell: Take the desktop tour" })
hl.bind("SUPER + K", hl.dsp.global("quickshell:oskToggle"), { description = "Shell: Toggle on-screen keyboard" })
hl.bind("SUPER + M", hl.dsp.global("quickshell:mediaControlsToggle"), { description = "Shell: Toggle media controls" })
hl.bind("SUPER + G", hl.dsp.global("quickshell:overlayToggle"), { description = "Shell: Toggle widget overlay" })
hl.bind("CTRL + ALT + Delete", hl.dsp.global("quickshell:sessionToggle"), { description = "Shell: Toggle session menu" })
hl.bind("SUPER + J", hl.dsp.global("quickshell:barToggle"), { description = "Shell: Toggle bar" })
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd(qsIsAlive .. " || pkill wlogout || wlogout -p layer-shell")) -- # [hidden] fallback
-- Described on purpose: dismissing the first-run guide is only non-destructive
-- if the way back is listed somewhere the user already looks.
hl.bind("SHIFT + SUPER + ALT + Slash", hl.dsp.exec_cmd("qs -p $HOME/.config/quickshell/$qsConfig/welcome.qml"),
    { description = "Shell: Open the welcome guide" })

hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(qsIpcCall .. " brightness increment || brightnessctl s 5%+"),
    { locked = true, repeating = true, description = "Screen: Brightness up" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(qsIpcCall .. " brightness decrement || brightnessctl s 5%-"),
    { locked = true, repeating = true, description = "Screen: Brightness down" })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(
        "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5; " .. volumeFeedback),
    { locked = true, repeating = true, description = "Media: Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(
        "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-; " .. volumeFeedback),
    { locked = true, repeating = true, description = "Media: Volume down" })

hl.bind("SUPER + Space", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"),
    { description = "Utilities: Switch keyboard layout (EN/KM)" })

hl.bind("CTRL + SUPER + T", hl.dsp.global("quickshell:wallpaperSelectorToggle"),
    { description = "Shell: Change wallpaper" })
hl.bind("CTRL + SUPER + ALT + T", hl.dsp.global("quickshell:wallpaperSelectorRandom"),
    { description = "Shell: Random wallpaper" })
hl.bind("CTRL + SUPER + SHIFT + D", hl.dsp.global("quickshell:toggleLightDark"),
    { description = "Shell: Toggle light/dark mode" })
hl.bind("CTRL + SUPER + T", hl.dsp.exec_cmd(qsIsAlive .. " || " .. qsScripts .. "/colors/switchwall.sh")) -- # [hidden] fallback
-- Wayland override needed: env.lua sets xcb session-wide and the respawned shell
-- maps no layer surfaces at all. killall -w so it does not race the old instance.
hl.bind("CTRL + SUPER + R", hl.dsp.exec_cmd(
        "killall -w global-menu-daemon qs quickshell; hyprctl reload; env QT_QPA_PLATFORM=wayland qs -c $qsConfig &"),
    { description = "Shell: Restart widgets" })
hl.bind("CTRL + SUPER + P", hl.dsp.global("quickshell:panelFamilyCycle"), { description = "Shell: Cycle panel family" })

--##! Utilities
--# Screenshot, Record, OCR, Color picker, Clipboard history
hl.bind("SUPER + V", hl.dsp.exec_cmd(
        qsIsAlive .. " || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy")) -- # [hidden] fallback
hl.bind("SUPER + Period", hl.dsp.exec_cmd(
        qsIsAlive .. " || pkill fuzzel || " .. hyprScripts .. "/fuzzel-emoji.sh copy")) -- # [hidden] fallback
hl.bind("SUPER + SHIFT + S", hl.dsp.global("quickshell:regionScreenshot"), { description = "Utilities: Screen snip" })
hl.bind("SUPER + SHIFT + S",
    hl.dsp.exec_cmd(qsIsAlive .. " || pidof slurp || hyprshot --freeze --clipboard-only --mode region --silent")) -- # [hidden] fallback
hl.bind("SUPER + SHIFT + A", hl.dsp.global("quickshell:regionSearch"), { description = "Utilities: Google Lens" })
hl.bind("SUPER + SHIFT + A", hl.dsp.exec_cmd(qsIsAlive .. " || pidof slurp || " .. hyprScripts .. "/snip_to_search.sh")) -- # [hidden] fallback
--# OCR
hl.bind("SUPER + SHIFT + X", hl.dsp.global("quickshell:regionOcr"),
    { description = "Utilities: Character recognition >> clipboard" })
hl.bind("SUPER + SHIFT + T", hl.dsp.global("quickshell:screenTranslate"),
    { description = "Utilities: Translate screen content" })
hl.bind("SUPER + SHIFT + X", hl.dsp.exec_cmd( -- # [hidden] fallback
    qsIsAlive ..
    " || pidof slurp || grim -g \"$(slurp $SLURP_ARGS)\" \"/tmp/ocr_image.png\" && tesseract \"/tmp/ocr_image.png\" stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\n' '+' | sed 's/+$//') | wl-copy && rm \"/tmp/ocr_image.png\""
))
--# Color picker
hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"),
    { description = "Utilities: Pick color #RRGGBB >> clipboard" })
--# Recording stuff
hl.bind("SUPER + SHIFT + R", hl.dsp.global("quickshell:regionRecord"),
    { locked = true, description = "Utilities: Record region (no sound)" })
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd(qsIsAlive .. " || " .. qsScripts .. "/videos/record.sh"), { locked = true }) -- # [hidden] fallback
hl.bind("SUPER + ALT + R", hl.dsp.global("quickshell:regionRecord"),
    { locked = true, description = "Utilities: Record region (no sound)" })
hl.bind("SUPER + ALT + R", hl.dsp.exec_cmd(qsIsAlive .. " || " .. qsScripts .. "/videos/record.sh"), { locked = true }) -- # [hidden] fallback
hl.bind("CTRL + ALT + R", hl.dsp.exec_cmd(qsScripts .. "/videos/record.sh --fullscreen"),
    { locked = true, description = "Utilities: Record screen (no sound)" })
hl.bind("SUPER + SHIFT + ALT + R", hl.dsp.exec_cmd(qsScripts .. "/videos/record.sh --fullscreen --sound"),
    { locked = true, description = "Utilities: Record screen (with sound)" })
--# Screenshot
local grimhyprctl = "grim -o \"$(hyprctl activeworkspace -j | jq -r '.monitor')\""
-- Print opens the snip UI so you can drag a region or hit "Full screen", rather
-- than silently grabbing everything. SHIFT + Print keeps the old one-shot grab.
hl.bind("Print", hl.dsp.global("quickshell:regionScreenshot"),
    { locked = true, description = "Utilities: Screenshot (region or full screen)" })
hl.bind("Print", hl.dsp.exec_cmd(qsIsAlive .. " || (" ..
    "d=$(xdg-user-dir PICTURES)/Screenshots/\"$(date '+%Y-%m-%d')\" && mkdir -p \"$d\" && " ..
    "f=\"$d\"/Screenshot_\"$(date '+%Y-%m-%d_%H.%M.%S')\".png && " ..
    grimhyprctl .. " \"$f\" && wl-copy < \"$f\" && notify-send 'Screenshot saved' \"$f\" -i \"$f\")"
), { locked = true }) -- # [hidden] fallback
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(
    "d=$(xdg-user-dir PICTURES)/Screenshots/\"$(date '+%Y-%m-%d')\" && mkdir -p \"$d\" && " ..
    "f=\"$d\"/Screenshot_\"$(date '+%Y-%m-%d_%H.%M.%S')\".png && " ..
    grimhyprctl .. " \"$f\" && wl-copy < \"$f\" && notify-send 'Screenshot saved' \"$f\" -i \"$f\""
), { locked = true, description = "Utilities: Screenshot whole screen >> file + clipboard" })
hl.bind("CTRL + Print", hl.dsp.exec_cmd(
    "d=$(xdg-user-dir PICTURES)/Screenshots/\"$(date '+%Y-%m-%d')\" && mkdir -p \"$d\" && " ..
    grimhyprctl .. " \"$d\"/Screenshot_\"$(date '+%Y-%m-%d_%H.%M.%S')\".png"
), { locked = true, non_consuming = true, description = "Utilities: Screenshot >> clipboard & file" })
hl.bind("CTRL + Print", hl.dsp.exec_cmd(grimhyprctl .. " - | wl-copy"), { locked = true, non_consuming = true }) -- # [hidden] clipboard half of the bind above
--# AI
hl.bind("SUPER + SHIFT + ALT + mouse:273", hl.dsp.exec_cmd(hyprScripts .. "/ai/primary-buffer-query.sh"),
    { description = "Utilities: Generate AI summary for selected text" })
-- (requires a running ollama model)

--##! Screen
--# Zoom
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 3.0 then
        hl.config({ cursor = { zoom_factor = 3.0 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end
hl.bind("SUPER + Minus", function() zoomfunction(-0.3) end, { repeating = true, description = "Screen: Zoom out" })
hl.bind("SUPER + Equal", function() zoomfunction(0.3) end, { repeating = true, description = "Screen: Zoom in" })

--# Zoom with keypad
hl.bind("SUPER + code:82", function() zoomfunction(-0.3) end, { repeating = true }) -- # [hidden] keypad
hl.bind("SUPER + code:86", function() zoomfunction(0.3) end, { repeating = true }) -- # [hidden] keypad

--##! Media
local mediaNextCommand = qsIpcCall .. " mpris next || playerctl next"
local mediaPrevCommand = qsIpcCall .. " mpris previous || playerctl previous"
local mediaPlayPauseCommand = qsIpcCall .. " mpris playPause || playerctl play-pause"
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd(mediaNextCommand), { locked = true, description = "Media: Next track" })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(mediaNextCommand), { locked = true, description = "Media: Next track" })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(mediaPrevCommand), { locked = true, description = "Media: Previous track" })
hl.bind("SUPER + SHIFT + ALT + mouse:275", hl.dsp.exec_cmd(mediaPrevCommand), { description = "Media: Previous track" })
hl.bind("SUPER + SHIFT + ALT + mouse:276", hl.dsp.exec_cmd(mediaNextCommand), { description = "Media: Next track" })
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd(mediaPrevCommand),
    { locked = true, description = "Media: Previous track" })
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd(mediaPlayPauseCommand),
    { locked = true, description = "Media: Play/pause media" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(mediaPlayPauseCommand), { locked = true, description = "Media: Play/pause media" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(mediaPlayPauseCommand), { locked = true, description = "Media: Play/pause media" })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"), { locked = true, description = "Media: Toggle mute" })
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"),
    { locked = true, description = "Media: Toggle mute" })
hl.bind("ALT + XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), { locked = true, description = "Media: Toggle mic" })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), { locked = true, description = "Media: Toggle mic" })
hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"),
    { locked = true, description = "Media: Toggle mic" })

--#!
--##! Window
--# Focusing
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Window: Move" })
-- Press and release of this global shortcut span the drag above. Not `transparent`:
-- the click must not reach the window under it.
hl.bind("SUPER + mouse:272", hl.dsp.global("quickshell:snapPreviewDrag")) -- # [hidden] rides the drag above
hl.bind("SUPER + mouse:274", hl.dsp.window.drag(), { mouse = true, description = "Window: Move" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Window: Resize" })
--#/# bind = SUPER + ←/↑/→/↓,, -- Focus in direction
for i = 1, 4 do
    local arrowkey = { "Left", "Right", "Up", "Down" }
    local focusdir = { "l", "r", "u", "d" }
    hl.bind("SUPER + " .. arrowkey[i], hl.dsp.focus({ direction = focusdir[i] }),
        { description = "Window: Focus " .. arrowkey[i] })
end
for i = 1, 2 do
    local arrowkey = { "BracketLeft", "BracketRight" }
    local focusdir = { "l", "r" }
    local descdir = { "Left", "Right" }
    hl.bind("SUPER + " .. arrowkey[i], hl.dsp.focus({ direction = focusdir[i] }),
        { description = "Window: Focus " .. descdir[i] })
end
--#/# bind = SUPER + SHIFT, ←/↑/→/↓,, -- Move in direction
for i = 1, 4 do
    local arrowkey = { "Left", "Right", "Up", "Down" }
    local focusdir = { "l", "r", "u", "d" }
    hl.bind("SUPER + SHIFT + " .. arrowkey[i], hl.dsp.window.move({ direction = focusdir[i] }),
        { description = "Window: Move " .. arrowkey[i] })
end

hl.bind("ALT + F4",
    function()
        hl.exec_cmd(
            "notify-send \"Wrong close keybind\" \"Super+Q to close. Use Alt+F4 for Windows VMs\" -a Hyprland")
    end,
    { non_consuming = true }) -- # [hidden] a hint, not an action
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Window: Close" })
hl.bind("SUPER + SHIFT + ALT + Q", hl.dsp.exec_cmd("hyprctl kill"), { description = "Window: Forcefully zap a window" })

--# Window split ratio
--#/# binde = SUPER, ;/',, -- Adjust split ratio
hl.bind("SUPER + Semicolon", hl.dsp.layout("splitratio -0.1"), { repeating = true, description = "Window: Shrink split ratio" })
hl.bind("SUPER + Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true, description = "Window: Grow split ratio" })
--# Positioning mode
hl.bind("SUPER + ALT + Space", hl.dsp.window.float({ action = "toggle" }), { description = "Window: Float/Tile" })
-- Whole-desktop counterpart of the per-window toggle above: floats everything
-- and keeps new windows floating, for when a stacking desktop suits the task
-- better than a tiling one. Press again to go back to tiling.
hl.bind("SUPER + SHIFT + Space", hl.dsp.exec_cmd("koompi-stacking toggle"),
    { description = "Window: Stacking/Tiling mode" })
hl.bind("SUPER + D", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
    { description = "Window: Maximize" })
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }),
    { description = "Window: Fullscreen" })
hl.bind("SUPER + ALT + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 3, action = "toggle" }),
    { description = "Window: Fullscreen spoof" })
hl.bind("SUPER + P", hl.dsp.window.pin(), { description = "Window: Pin" })

--#/# bind = SUPER+ALT, Hash,, -- Send to workspace -- (1, 2, 3,...)
for i = 1, 10 do
    hl.bind("SUPER + ALT + " .. (i % 10), function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end, { description = "Window: Send to workspace " .. i })
end
--# We also use raw keycodes because some keyboard layouts register number keys as different chars. The codes can be verified with `wev`
for i = 1, 10 do
    local numberkey = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    hl.bind("SUPER + ALT + code:" .. numberkey[i], function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end) -- # [hidden] keycode twin
end
--# keypad numbers
for i = 1, 10 do
    local numpadkey = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    hl.bind("SUPER + ALT + code:" .. numpadkey[i], function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end) -- # [hidden] keypad
end

--# #/# bind = SUPER+SHIFT, Scroll ↑/↓,, -- Send to workspace left/right
for i = 1, 4 do
    local key = { "SUPER + SHIFT + mouse_", "SUPER + ALT + mouse_" }
    local keycombos = { key[1] .. "down", key[1] .. "up", key[2] .. "down", key[2] .. "up" }
    local prefix = { "r-", "r+", "r-", "r+" }
    local descdir = { "left", "right", "left", "right" }
    hl.bind(keycombos[i], hl.dsp.window.move({ workspace = prefix[i] .. "1" }),
        { description = "Window: Send to workspace " .. descdir[i] })
end

--#/# bind = SUPER+SHIFT, Page_↑/↓,, -- Send to workspace left/right
for i = 1, 2 do
    local keydirs = { "Up", "Down" }
    local prefix = { "r-", "r+" }
    local descdir = { "left", "right" }
    hl.bind("SUPER + SHIFT + Page_" .. keydirs[i], hl.dsp.window.move({ workspace = prefix[i] .. "1" }), {description = "Window: Send to workspace " .. descdir[i]})
end
for i = 1, 4 do
    local key = { "SUPER + ALT + Page_", "CTRL + SUPER + SHIFT + " }
    local keycombos = { key[1] .. "down", key[1] .. "up", key[2] .. "Right", key[2] .. "Left" }
    local prefix = { "r+", "r-", "r+", "r-" }
    hl.bind(keycombos[i], hl.dsp.window.move({ workspace = prefix[i] .. "1" })) -- # [hidden]
end

hl.bind("SUPER + ALT + S",
    hl.dsp.window.move({ workspace = "special:special", follow = false }), { description = "Window: Send to scratchpad" })
hl.bind("CTRL + SUPER + S", hl.dsp.workspace.toggle_special("special"), { description = "Workspace: Toggle scratchpad" })

--##! Workspace
--# Switching
--#/# bind = SUPER, Hash,, -- Focus workspace -- (1, 2, 3,...)
for i = 1, 10 do
    hl.bind("SUPER + " .. (i % 10), function()
        hl.dispatch(hl.dsp.focus({ workspace = workspace_in_group(i) }))
    end, { description = "Workspace: Focus " .. i })
end
--# We also use raw keycodes because some keyboard layouts register number keys as different chars. The codes can be verified with `wev`
for i = 1, 10 do
    local numberkey = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    hl.bind("SUPER + code:" .. numberkey[i], function()
        hl.dispatch(hl.dsp.focus({ workspace = workspace_in_group(i) }))
    end) -- # [hidden] keycode twin
end
--# keypad numbers
for i = 1, 10 do
    local numpadkey = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    hl.bind("SUPER + code:" .. numpadkey[i], function()
        hl.dispatch(hl.dsp.focus({ workspace = workspace_in_group(i) }))
    end) -- # [hidden] keypad
end

--#/# bind = CTRL+SUPER, ←/→,, -- Focus left/right
--#/# bind = CTRL+SUPER+ALT, ←/→,, -- # [hidden] Focus busy left/right
for i = 1, 2 do
    local keys = { "Left", "Right" }
    local prefix = { "r-", "r+" }
    local descdir = { "left", "right" }
    hl.bind("CTRL + SUPER + " .. keys[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }), {description = "Workspace: Focus " .. descdir[i]})
end
for i = 1, 2 do
    local keys = { "Left", "Right" }
    local prefix = { "m-", "m+" }
    hl.bind("CTRL + SUPER + ALT + " .. keys[i], hl.dsp.focus({ workspace = prefix[i] .. "1" })) -- # [hidden]
end
--#/# bind = SUPER, Page_↑/↓,, -- Focus left/right
for i = 1, 4 do
    local key = { "SUPER + Page_Down", "SUPER + Page_Up" }
    local keycombos = { key[1], key[2], "CTRL + " .. key[1], "CTRL + " .. key[2] }
    local prefix = { "r+", "r-", "r+", "r-" }
    local descdir = { "right", "left", "right", "left" }
    hl.bind(keycombos[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }),
        { description = "Workspace: Focus " .. descdir[i] })
end
--#/# bind = SUPER, Scroll ↑/↓,, -- Focus left/right
for i = 1, 4 do
    local key = { "SUPER + mouse_up", "SUPER + mouse_down" }
    local keycombos = { key[1], key[2], "CTRL + " .. key[1], "CTRL + " .. key[2] }
    local prefix = { "+", "-", "r+", "r-" }
    local descdir = { "right", "left", "right", "left" }
    hl.bind(keycombos[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }),
        { description = "Workspace: Focus " .. descdir[i] })
end
--## Special
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("special"), { description = "Workspace: Toggle scratchpad" })
hl.bind("SUPER + mouse:275", hl.dsp.workspace.toggle_special("special"), { description = "Workspace: Toggle scratchpad" })
for i = 1, 4 do
    local key = { "BracketLeft", "BracketRight", "Up", "Down" }
    local prefix = { "-1", "+1", "r-5", "r+5" }
    local desc = { "Focus left", "Focus right", "Jump 5 left", "Jump 5 right" }
    hl.bind("CTRL + SUPER + " .. key[i], hl.dsp.focus({ workspace = prefix[i] }), { description = "Workspace: " .. desc[i] })
end

--##! Virtual machines
hl.define_submap("virtual-machine", function()
    hl.bind("SUPER + ALT + F1", function()
        local currentsubmap = hl.get_current_submap()
        if currentsubmap == "virtual-machine" then
            hl.dispatch(hl.dsp.exec_cmd(
                "notify-send 'Exited Virtual Machine submap' 'Keybinds re-enabled' -a 'Hyprland'"))
            hl.dispatch(hl.dsp.submap("reset"))
        elseif currentsubmap == "" then
            hl.dispatch(hl.dsp.exec_cmd(
                "notify-send 'Entered Virtual Machine submap' 'Keybinds disabled. hit SUPER+ALT+F1 to escape' -a 'Hyprland'"))
            hl.dispatch(hl.dsp.submap("virtual-machine"))
        end
    end, { submap_universal = true, description = "Shell: Toggle virtual machine mode (pass all keys through)" })
end)


--#!
--# Testing
hl.bind("SUPER + ALT + F11",
    hl.dsp.exec_cmd(
        "RANDOM_IMAGE=\"$(find ~/Pictures -type f | shuf -n 1)\"; ~/.local/bin/koompi-notify-send -a \"Hyprland\" -i \"discord\" -t 6000 \"Test notification with body image\" \"This notification should contain your user account <b>image</b> and <a href=\\\"https://discord.com/app\\\">Discord</a> <b>icon</b>. Oh and here is a random image in your Pictures folder: <img src=\\\"$RANDOM_IMAGE\\\" alt=\\\"Testing image\\\"/>\" --exec xdg-open \"$RANDOM_IMAGE\"")
) -- # [hidden]
hl.bind("SUPER + ALT + F12",
    hl.dsp.exec_cmd(
        "RANDOM_IMAGE=\"$(find ~/Pictures -type f | shuf -n 1)\"; ~/.local/bin/koompi-notify-send -a \"Discord (fake)\" -i \"discord\" -t 6000 \"Test notification\" \"This notification should contain a random image in your <b>Pictures</b> folder and <a href=\\\"https://discord.com/app\\\">Discord</a> <b>icon</b>.\n<i>Flick right to dismiss!</i> <img src=\\\"$RANDOM_IMAGE\\\" alt=\\\"Testing image\\\"/>\" --exec xdg-open \"$RANDOM_IMAGE\"")
)                                                                                                        -- # [hidden]
hl.bind("SUPER + ALT + Equal",
    hl.dsp.exec_cmd("notify-send 'Urgent notification' 'Ah hell no' -u critical -a 'Hyprland keybind'")) -- # [hidden]

--##! Session
hl.bind("SUPER + L", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Session: Lock" })
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd("systemctl suspend || loginctl suspend"),
    { locked = true, description = "Session: Sleep" }) -- Sleep
-- Closing the lid locks before logind gets round to suspending (or does not,
-- when Keep awake holds handle-lid-switch). koompi-lid skips the lock while an
-- external monitor is attached so a docked laptop keeps working with its lid shut.
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("koompi-lid close"), { locked = true }) -- # [hidden] not a key
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("koompi-lid open"), { locked = true }) -- # [hidden] not a key

hl.bind("CTRL + SHIFT + ALT + SUPER + Delete", hl.dsp.exec_cmd("systemctl poweroff || loginctl poweroff"),
    { description = "Session: Shut down" }) -- # [hidden] Power off


--##! Apps
hl.bind("SUPER + Return", app("terminal", terminal), { description = "App: Terminal" })
hl.bind("SUPER + T", app("terminal", terminal), { description = "App: Terminal" })
hl.bind("CTRL + ALT + T", app("terminal", terminal), { description = "App: Terminal" })
hl.bind("SUPER + E", app("fileManager", fileManager), { description = "App: File manager" })
hl.bind("SUPER + W", app("browser", browser), { description = "App: Browser" })
hl.bind("SUPER + C", app("codeEditor", codeEditor), { description = "App: Code editor" })
hl.bind("CTRL + SUPER + SHIFT + ALT + W", app("officeSoftware", officeSoftware), { description = "App: Office software" })
hl.bind("SUPER + X", app("textEditor", textEditor), { description = "App: Text editor" })
hl.bind("CTRL + SUPER + V", app("volumeMixer", volumeMixer), { description = "App: Volume mixer" })
hl.bind("SUPER + I", app("settingsApp", settingsApp), { description = "App: Settings app" })
hl.bind("CTRL + SHIFT + Escape", app("taskManager", taskManager), { description = "App: Task manager" })

--# Cursed stuff
--## Make window not amogus large
hl.bind("CTRL + SUPER + Backslash", hl.dsp.window.resize({ x = 640, y = 480, "exact" }), { description = "Window: Resize to 640x480" })
