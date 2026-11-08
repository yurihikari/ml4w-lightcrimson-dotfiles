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
