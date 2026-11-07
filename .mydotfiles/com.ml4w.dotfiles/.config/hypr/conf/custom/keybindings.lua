local mainMod = "SUPER"
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("~/.config/hypr/scripts/launcher.sh"), { description = "Open application launcher" })
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("qs ipc call radialMenu open"), { description = "Open radial menu" })
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/colorpicker.sh"), { description = "Open the color Picker" })
hl.bind(mainMod .. " + ALT + M", hl.dsp.exec_cmd("qs ipc call display toggle"), { description = "Toggle DisplayManager" })
hl.bind(mainMod .. " + SHIFT + I", hl.dsp.exec_cmd("qs ipc call settings toggle"), { description = "Open settings window" })
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd("qs ipc call workspacewallpaper toggle"), { description = "Open workspace wallpaper picker" })

-- Bar popup toggles (Quickshell IPC)
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("qs ipc call bar-media toggle"), { description = "Toggle media popup" })
-- ML4W binds SUPER+C to the calculator and SUPER+CTRL+C to its own calendar;
-- take SUPER+C back for the bar calendar and keep the calculator on SUPER+CTRL+C.
hl.unbind(mainMod .. " + C")
hl.unbind(mainMod .. " + CTRL + C")
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("qs ipc call bar-calendar toggle"), { description = "Toggle calendar popup" })
hl.bind(mainMod .. " + CTRL + C", hl.dsp.exec_cmd("~/.config/ml4w/settings/calculator.sh"), { description = "Open the calculator" })
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("qs ipc call bar-clipboard toggle"), { description = "Toggle clipboard popup" })
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("qs ipc call bar-dashboard toggle"), { description = "Toggle system info popup" })
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("qs ipc call bar-system toggle"), { description = "Toggle network/system popup" })
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.exec_cmd("qs ipc call bar-keyboard toggle"), { description = "Toggle keyboard layout popup" })
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("qs ipc call dock toggle"), { description = "Toggle dock" })
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("qs ipc call bar-power toggle"), { description = "Toggle power menu" })