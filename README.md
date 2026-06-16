<img width="2880" height="1800" alt="image" src="https://github.com/user-attachments/assets/22c602c9-93e4-43cb-9961-ba5c52a581eb" />
<img width="2880" height="1800" alt="image" src="https://github.com/user-attachments/assets/33348b2e-af4b-4361-90e4-64869d55dd96" />






<h1 align="center"> ML4W LightCrimson Dotfiles </h1>

<p align="center">
  <a href="https://github.com/yurihikari/ml4w-lightcrimson-dotfiles/stargazers"><img src="https://img.shields.io/github/stars/yurihikari/ml4w-lightcrimson-dotfiles?color=f5bde6&style=for-the-badge&logo=starship"></a>
  <a href="https://github.com/yurihikari/ml4w-lightcrimson-dotfiles/issues"><img src="https://img.shields.io/github/issues/yurihikari/ml4w-lightcrimson-dotfiles?color=ed8796&style=for-the-badge&logo=codecov"></a>
  <a href="https://github.com/yurihikari/ml4w-lightcrimson-dotfiles/network/members"><img src="https://img.shields.io/github/forks/yurihikari/ml4w-lightcrimson-dotfiles?color=8aadf4&style=for-the-badge&logo=jfrog-bintray"></a>
  <a href="https://github.com/yurihikari/ml4w-lightcrimson-dotfiles/blob/master/LICENSE"><img src="https://img.shields.io/badge/license-GPL3.0-orange.svg?color=a6da95&style=for-the-badge&logo=mitsubishi"></a>
</p>

## About ❓
This repo basically uses the dotfiles made from ML4W and uses my own tweaks.
Used on a CachyOS system. Should work with Arch based systems as well.

This dotfiles only install the default profile of ML4W, and then apply some of my own tweaks on top of it. So you can expect the same experience as ML4W with some added features and optimizations.

## Features 👍

### 🐚 Custom Quickshell Bar (replaces Waybar)
A fully custom [Quickshell](https://quickshell.outfoxxed.me/) desktop shell, built from scratch and used instead of ML4W's Waybar.

   - **Top bar (MainBar):** workspaces with live app icons, system tray with full menu support, a center media pill, mic/brightness/volume ring controls (scroll to adjust), keyboard-layout indicator, notification (SwayNC) toggle, clock, and a system pill (network / Wi-Fi / Bluetooth / battery)
   - **Instant OSD** overlay for volume, mic and brightness changes
   - **Rounded screen frame** drawing soft corners around every monitor
   - **Multi-monitor aware** — popups open on the monitor where your mouse currently is

#### Quickshell popups (toggle by keybinding or click)
   - **Media** (`META+M`) — MPRIS player with album art, a circular Cava audio visualizer, multi-player switching, audio output/sink switcher and volume control
   - **Calendar** (`META+C`) — month calendar with week numbers, live weather (Open-Meteo) and a world-clock lookup
   - **System / Network** (`META+N`) — Wi-Fi scanning & connection, Bluetooth and network controls
   - **Dashboard** (`META+I`) — system info at a glance (kernel, resources, mounted disks & drives)
   - **Dock** (`META+A`) — app launcher with fuzzy search + full keyboard navigation, plus quick notes, a to-do list and a screenshot tool with thumbnails
   - **Clipboard** (`META+SHIFT+V`) — clipboard history (cliphist)
   - **Keyboard Layout** (`META+SHIFT+K`) — switch keyboard layout / variant
   - **Power** (`META+X`) — power menu (lock / suspend / log out / reboot / shutdown) with keyboard selection
   - **Radial Menu** (`META+R`) and **Display Manager** (`META+ALT+M`)

### 🎨 ML4W Theme & Wallpaper Customizations
   - ml4w-toggle-theme: Added 'Save' theme mode variable
     - Theme stays consistent after waybar/matugen changes
   - darkmode: Custom darkmode state file preserved
   - ml4w-wallpaper: Added darkmode variable
     - Matugen won't override darkmode unless desired

### 📸 Screenshot & Colorpicker Enhancements
   - screenshot.sh: Screenshots now copied to clipboard
     + saved to file (dual functionality)
   - colorpicker.sh: Added hyprpicker integration
     - Press META+P to pick colors

### ⌨️ Custom Keybindings
   - META+D — Application launcher
   - META+P — Colorpicker (hyprpicker)
   - META+R — Radial menu
   - META+ALT+M — Display manager
   - Quickshell popups: META+M (media), META+C (calendar), META+N (network/system),
     META+I (dashboard), META+A (dock), META+SHIFT+V (clipboard),
     META+SHIFT+K (keyboard layout), META+X (power menu)
   - Plus other custom overrides in default.conf

### 🖥️ Fastfetch Customization
   - Custom logo image added (you can replace it with your own)
   - GPU information display enabled

### 🐚 Shell Configuration Fixes
   - zsh plugins: Fixed path issue for AUR vs git clone
     - 00-init & 20-customization updated
   - zoxide: Installed and initialized for bash/fish/zsh
     - 'cd' alias with directory jumping available
   - Aliases: Added for bash, fish, and zsh

## Additional Dependencies ⚠️
- Using pear-desktop as the music app for META+M keybind

## Installation 🔧

Just launch with bash the install.sh after cloning this repo

I just want to make it as simple as possible, unlike my previous garuda-hyprdots, so this can be used to setup a fully working hyprland setup on any arch based distros. 

## Special Thanks 🙏

Big Thanks to ML4W for making this setup so easy to do.
