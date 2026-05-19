local mainMod = "SUPER"
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("~/.config/hypr/scripts/launcher.sh"), { description = "Open application launcher" })
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("qs ipc call radialMenu open"), { description = "Open radial menu" })
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("qs ipc call power toggle"), { description = "Start Power Menu" })
hl.bind(mainMod .. " + ALT + M", hl.dsp.exec_cmd("qs ipc call DisplayManager toggle"), { description = "Toggle DisplayManager" })
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("qs ipc call SystemPopup toggle"), { description = "Toggle System Popup" })
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/colorpicker.sh"), { description = "Open the color Picker" })