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
