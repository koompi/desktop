-- MONITOR CONFIG
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "auto"
})

hl.gesture({
    fingers = 3,
    direction = "swipe",
    action = "move"
})
hl.gesture({
    fingers = 3,
    direction = "pinch",
    action = "fullscreen"
})
hl.gesture({
    fingers = 4,
    direction = "horizontal",
    action = "workspace"
})
hl.gesture({
    fingers = 4,
    direction = "up",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
    end
})
hl.gesture({
    fingers = 4,
    direction = "down",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
    end
})
-- Launchpad: spread four fingers to bring the grid out, close them to put it
-- away. Bound as two gestures rather than one toggle so making the same motion
-- twice never flaps the grid shut.
--
-- Read the direction names backwards. Measured on 0.55.4 against a synthetic
-- touchpad: "pinchin" fires when the fingers move APART and "pinchout" when
-- they come together, the opposite of how they read. Swap these and the
-- gesture inverts, so check before believing the words.
hl.gesture({
    fingers = 4,
    direction = "pinchin",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:launchpadOpen"))
    end
})
hl.gesture({
    fingers = 4,
    direction = "pinchout",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:launchpadClose"))
    end
})

hl.config({
    -- The 4-finger swipe walks numeric neighbours (r+1/r-1) instead of cycling
    -- only the open workspaces, so every workspace is reachable by swiping,
    -- the same way the bar's scroll wheel already behaves.
    gestures = {
        workspace_swipe_use_r = true,
        -- Gearing: px of finger travel that equals one full workspace. The 300
        -- default throws the whole screen across on a small movement, which at
        -- 60Hz lands as a few huge per-frame jumps. 450 tracks the finger at
        -- roughly two thirds the speed for the same motion.
        workspace_swipe_distance = 450,
        -- Commit threshold, as a fraction of the above. Kept at an equivalent
        -- absolute travel to the old 0.5-of-300 rather than scaling with the
        -- longer distance, so a deliberate drag does not have to go further
        -- than it used to.
        workspace_swipe_cancel_ratio = 0.4,
        -- Speed that forces the switch regardless of the ratio. At the 30
        -- default a quick flick lands short and snaps back, which is the
        -- roughest thing the gesture does. 5 lets flicks commit.
        workspace_swipe_min_speed_to_force = 5,
        -- Keep swiping across several workspaces without lifting.
        workspace_swipe_forever = true
    },
    general = {
        -- Gaps and border
        gaps_in = 4,
        gaps_out = 5,
        gaps_workspaces = 50,

        border_size = 1,

        col = {
            active_border = "rgba(0DB7D455)",
            inactive_border = "rgba(31313600)"
        },
        resize_on_border = true,

        no_focus_fallback = true,
        allow_tearing = true, -- This just allows the `immediate` window rule to work
        snap = {
            enabled = true,
            window_gap = 4,
            monitor_gap = 5,
            respect_gaps = true
        }
    },
    decoration = {
        -- 2 = circle, higher = squircle, 4 = very obvious squircle
        -- Fuck clearly visible squircles. 100% Apple brainrot.
        rounding_power = 2.5,
        rounding = 18,

        blur = {
            enabled = true,
            xray = true,
            special = false,
            new_optimizations = true,
            size = 10,
            passes = 3,
            brightness = 1,
            noise = 0.05,
            contrast = 0.89,
            vibrancy = 0.5,
            vibrancy_darkness = 0.5,
            popups = false,
            popups_ignorealpha = 0.6,
            input_methods = true,
            input_methods_ignorealpha = 0.8
        },
        shadow = {
            enabled = true,
            range = 20,
            offset = {0, 2},
            render_power = 10,
            color = "rgba(00000020)"

        },
        -- Dim
        dim_inactive = true,
        dim_strength = 0.05,
        dim_special = 0.2
    },
    animations = {
        enabled = true
    },
    dwindle = {
        preserve_split = true,
        smart_split = false,
        smart_resizing = false
        -- precise_mouse_move = true,
    },
})
-- Curves
hl.curve("expressiveFastSpatial", {
    type = "bezier",
    points = {{0.42, 1.67}, {0.21, 0.90}}
})
hl.curve("expressiveSlowSpatial", {
    type = "bezier",
    points = {{0.39, 1.29}, {0.35, 0.98}}
})
hl.curve("expressiveDefaultSpatial", {
    type = "bezier",
    points = {{0.38, 1.21}, {0.22, 1.00}}
})
hl.curve("emphasizedDecel", {
    type = "bezier",
    points = {{0.05, 0.7}, {0.1, 1}}
})
hl.curve("emphasizedAccel", {
    type = "bezier",
    points = {{0.3, 0}, {0.8, 0.15}}
})
hl.curve("standardDecel", {
    type = "bezier",
    points = {{0, 0}, {0, 1}}
})
hl.curve("menu_decel", {
    type = "bezier",
    points = {{0.1, 1}, {0, 1}}
})
hl.curve("menu_accel", {
    type = "bezier",
    points = {{0.52, 0.03}, {0.72, 0.08}}
})
hl.curve("stall", {
    type = "bezier",
    points = {{1, -0.1}, {0.7, 0.85}}
})
-- A 60Hz panel with no VRR gives a workspace slide ~20-24 frames to move the
-- full monitor width + gaps_workspaces. Front-loaded curves spend most of that
-- distance in the first handful of frames and the rest crawling: measured on
-- 1920px, easeOutExpo peaks at 554px of travel in a single frame and
-- emphasizedDecel at 882px. That per-frame jump is the strobing, not the
-- duration. This curve has a small ease-in and a long decel tail, which spreads
-- the same distance over every frame and caps the peak at 292px. The mild start
-- also matters for the swipe: on release Hyprland animates the remainder with
-- this curve, so a near-zero initial velocity would stall against a finger that
-- was already moving, while an expo start would visibly rocket away from it.
hl.curve("workspaceSlide", {
    type = "bezier",
    points = {{0.25, 0.1}, {0.05, 1.0}}
})
-- Configs
-- windows
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 3,
    bezier = "emphasizedDecel",
    style = "popin 80%"
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 3,
    bezier = "emphasizedDecel"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 2,
    bezier = "emphasizedDecel",
    style = "popin 90%"
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 2,
    bezier = "emphasizedDecel"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 3,
    bezier = "emphasizedDecel",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 10,
    bezier = "emphasizedDecel"
})

-- layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 2.7,
    bezier = "emphasizedDecel",
    style = "popin 93%"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 2.4,
    bezier = "menu_accel",
    style = "popin 94%"
})
-- fade
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 0.5,
    bezier = "menu_decel"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 2.7,
    bezier = "stall"
})
-- workspaces
-- menu_decel at 700ms moved almost everything in the first frames then crawled
-- the rest of the way, which read as clunky. easeOutExpo at 350ms had the same
-- shape, just compressed - the crawl became a 4-frame dead tail. See the
-- workspaceSlide curve for why the fix is the shape rather than the duration.
-- 400ms is deliberately longer than the old 350ms: at 60Hz the extra 3 frames
-- are 3 more motion samples, and this curve has no dead tail to pad out.
-- Leave workspacesIn/workspacesOut inherited. Overriding them separately
-- desyncs the two halves of a `slide`, which opens a gap mid-animation.
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 4,
    bezier = "workspaceSlide",
    style = "slide"
})
-- specialWorkspace
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 2.8,
    bezier = "emphasizedDecel",
    style = "slidevert"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 1.2,
    bezier = "emphasizedAccel",
    style = "slidevert"
})
-- zoom
hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 3,
    bezier = "standardDecel"
})

hl.config({
    input = {
        kb_layout = "us,kh",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35,

        follow_mouse = 1,
        off_window_axis_events = 2,

        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            clickfinger_behavior = true,
            scroll_factor = 0.7
        },

        -- Bind the touchscreen digitizer to eDP-1. Without this the [[Auto]]
        -- mapping spreads the touch surface across the whole layout span, and
        -- since eDP-1 sits at layout pos (1920,1080) every touch lands offset.
        touchdevice = {
            output = "eDP-1"
        }
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        vrr = 0,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        enable_swallow = false,
        -- Only the terminals KOOMPI ships: wezterm, konsole, and kitty for the
        -- scratchpads. Unanchored, so "wezterm" already covers the real class
        -- org.wezfurlong.wezterm.
        swallow_regex = "(wezterm|kitty|konsole)",
        on_focus_under_fullscreen = 2,
        allow_session_lock_restore = true,
        session_lock_xray = true,
        initial_workspace_tracking = false,
        focus_on_activate = true,
        disable_xdg_env_checks = true
    },

    binds = {
        scroll_event_delay = 0,
        hide_special_on_workspace_change = true
    },

    cursor = {
        zoom_factor = 1,
        zoom_rigid = false,
        zoom_disable_aa = true,
        hotspot_padding = 1
    },

    xwayland = {
        force_zero_scaling = true
    }
})
