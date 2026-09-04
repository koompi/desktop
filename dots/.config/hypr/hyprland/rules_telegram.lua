-- Telegram widget (SUPER + Y): window rules and the placement handlers.
-- Both Telegram classes on purpose: env.lua forces QT_QPA_PLATFORM=xcb session wide,
-- so Qt apps come up on XWayland and Hyprland reports the X11 WM_CLASS, not the
-- Wayland app_id. Any rule keyed on a Qt app's app_id has the same problem.
-- initial_title as well: the reaction popup is a transient sharing the class.
local telegramClass = "^(org\\.telegram\\.desktop|TelegramDesktop)$"
local telegramTitle = "^Telegram( \\([0-9]+\\))?$"
hl.window_rule({match = {class = telegramClass, initial_title = telegramTitle }, workspace = "special:telegram silent"})
hl.window_rule({match = {class = telegramClass, initial_title = telegramTitle }, float = true})
-- Every other Telegram top-level floats too: the call panel and mini apps open
-- on the current workspace while the widget is hidden, and tiled the call panel
-- fills the monitor with the answer button nowhere in reach. Float only, no
-- size or centre: the reaction popup shares the class (a transient, floating
-- already) and must keep its own place. Hyprland's regex has no negative
-- lookahead to exclude it here; the handler below does that by initial title.
hl.window_rule({match = {class = telegramClass }, float = true})
-- Placement is done below, not by size/move rules: those evaluate monitor_w/h on
-- the focused monitor, and the silent workspace rule then lands the window on
-- the monitor special:telegram already lives on, a different one when the two
-- screens are 1200 and 1080 tall.
local function isTelegramClass(w)
    return w.class == "TelegramDesktop" or w.class == "org.telegram.desktop"
end
-- Exact, not a prefix: the context menu is a transient titled "TelegramDesktop",
-- and "^Telegram" took it for the main window, resized it to the panel and
-- broke every right-click.
local function isTelegramMain(w)
    local t = w.initial_title or ""
    return isTelegramClass(w) and (t == "Telegram" or t:match("^Telegram %(%d+%)$") ~= nil)
end
local function isTelegramPopup(w)
    return isTelegramClass(w) and (w.initial_title or ""):match("^TelegramDesktop") ~= nil
end
-- The media viewer is Telegram's own full-screen overlay for photos, videos and
-- document previews. It sizes itself to the monitor and closes on a click
-- outside the picture; squeezed into the side panel it reads as a file that
-- neither scrolls nor survives a click. Leave it alone.
local function isTelegramOverlay(w)
    return isTelegramClass(w) and w.initial_title == "Media viewer"
end
local function hasTag(w, tag)
    for _, t in ipairs(w.tags or {}) do
        if t == tag then return true end
    end
    return false
end
-- Left 58% for Telegram, right 42% for whatever it opens, at exactly the
-- geometry two tiled windows would get: gaps_out + border at the edges,
-- gaps_in + border on each side of the split, read from general so they follow
-- the theme. Centered at overlay size it covered that spot and everything
-- opened from it landed under it.
local function placeTelegramPanel(w, m, left)
    local gapsOut, gapsIn = hl.get_config("general:gaps_out"), hl.get_config("general:gaps_in")
    local border = hl.get_config("general:border_size")
    local W, H, r = m.size.width, m.size.height, m.reserved
    local split = r.left + (W - r.left - r.right) * 0.58
    local x, right = split + gapsIn.left + border, W - r.right - gapsOut.right - border
    if left then x, right = r.left + gapsOut.left + border, split - gapsIn.right - border end
    local y = r.top + gapsOut.top + border
    local height = H - r.top - r.bottom - gapsOut.top - gapsOut.bottom - 2 * border
    -- Targeted, never focused: focusing the main window as it maps shows the
    -- special workspace, and the toggle that follows in the bind hides it again.
    if not w.floating then hl.dispatch(hl.dsp.window.float({ window = w })) end
    if not left then hl.dispatch(hl.dsp.window.tag({ tag = "+telegram-side", window = w })) end
    x, right = math.floor(x), math.floor(right)
    hl.dispatch(hl.dsp.window.resize({ x = right - x, y = math.floor(height), "exact", window = w }))
    hl.dispatch(hl.dsp.window.move({ x = m.x + x, y = math.floor(m.y + y), window = w }))
end
-- Telegram's own secondary windows (mini apps) open tiled on special:telegram,
-- under the floating panel. No rule can name them: they share Telegram's class
-- and all that sets them apart is where they land. They float by the rule above
-- and take the right panel. An app Telegram hands a file to (Okular for a PDF)
-- lands there too, with a class of its own: it goes to the monitor's regular
-- workspace, tiled, as if launched from anywhere, and focusing it hides the
-- widget until SUPER + Y. Floated into the right panel it would not scroll.
-- Any other arrival already floating is a dialog and keeps its own place.
hl.on("window.open", function(w)
    local ws = w.workspace
    if not ws then return end
    local m = ws.monitor or w.monitor
    if not m then return end
    if ws.name == "special:telegram" then
        if isTelegramMain(w) then
            placeTelegramPanel(w, m, true)
        elseif isTelegramPopup(w) or isTelegramOverlay(w) then
            return
        elseif isTelegramClass(w) then
            placeTelegramPanel(w, m, false)
            hl.dispatch(hl.dsp.focus({ window = w }))
        elseif not w.floating and m.active_workspace then
            hl.dispatch(hl.dsp.window.move({ workspace = m.active_workspace.name, window = w }))
            hl.dispatch(hl.dsp.focus({ window = w }))
        end
    elseif isTelegramClass(w) and not isTelegramMain(w) and not isTelegramPopup(w) and not isTelegramOverlay(w) then
        -- Call panel or mini app with the widget hidden: at its own size, centred.
        hl.dispatch(hl.dsp.window.center({ window = w }))
        hl.dispatch(hl.dsp.focus({ window = w }))
    end
end)
-- Toggling the widget from the other monitor brings the workspace over, and a
-- floating window keeps the size it got there. Re-place both panels for the
-- monitor the workspace is shown on.
hl.on("workspace.special_active", function(ws, m)
    local ok, name = pcall(function() return ws.name end)
    if not ok or name ~= "special:telegram" or not m then return end
    for _, w in ipairs(hl.get_workspace_windows(ws)) do
        if isTelegramMain(w) then
            placeTelegramPanel(w, m, true)
        elseif hasTag(w, "telegram-side") then
            placeTelegramPanel(w, m, false)
        end
    end
end)
