-- Quickshell layer rule
hl.layer_rule({
    match = {
        namespace = "quickshell"
    },
    blur_popups = true,
    blur = true,
    xray = true,
    ignore_alpha = 0.79
})

-- Quickshell frame drawers (bar popups, hover drawer, toasts, dock): same
-- blur as above, but no layer animation, since they slide out of the frame
-- themselves (with Hyprland's slide on top they appeared twice).
hl.layer_rule({
    match = {
        namespace = "quickshell-drawer"
    },
    blur_popups = true,
    blur = true,
    xray = true,
    ignore_alpha = 0.79,
    no_anim = true
})

-- SwayNC layer rule
hl.layer_rule({
    match = {
        namespace = "swaync-control-center"
    },
    blur_popups = true,
    blur = true,
    xray = true,
    ignore_alpha = 0.79
})

hl.layer_rule({
    match = {
        namespace = "swaync-notification-window"
    },
    blur_popups = true,
    blur = true,
    xray = true,
    ignore_alpha = 0.79
})

-- Rofi layer rule (rofi is not GTK, so Hyprland layer rules still apply).
-- Its matugen background is 70% opaque, so the threshold sits below that.
hl.layer_rule({
    match = {
        namespace = "rofi"
    },
    blur = true,
    xray = true,
    ignore_alpha = 0.5
})

-- Polkit auth dialog → float, center, and follow the active workspace
hl.window_rule({
    name = "polkit-gnome-authentication-agent-1",
    match = {class = "^(polkit-gnome-authentication-agent-1)$"},
    float = true,
    center = true,
    pin = true,
})

-- Window spacing that matches the screen frame: every window edge sits 10px
-- from the frame (the frame is 10px wide, the bar reserves 30px but draws 40px)
-- and 10px from its neighbours, so the frame reads as the outer edge of the
-- tiling grid. With that 10px gap, the 10px window rounding is concentric with
-- the frame's 20px inner corners.
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 20,
    }
})

-- ── HyperBA theme ────────────────────────────────────────────────────────
-- Game-lobby windows: matugen colours (they follow the wallpaper), the
-- accent leaning into the highlight on the focused window, a soft hairline
-- on the others, and the small radius of the HUD's own plates.
hl.config({
    general = {
        gaps_in  = 6,
        gaps_out = 18,
        border_size = 2,
        col = {
            active_border   = { colors = {primary, tertiary}, angle = 45 },
            inactive_border = outline_variant,
        },
    },
    decoration = {
        rounding = 8,
    },
})
