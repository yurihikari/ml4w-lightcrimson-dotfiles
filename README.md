<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/4d9c7e27-fbc4-49ef-9779-02090d0ab355" />
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/680fcb60-ca4d-4f42-85ae-6aee2c9bf29a" />


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

### ⌨️ Custom Keybindings Added
   - META+X - Powermenu
   - META+P - Colorpicker (hyprpicker)
   - META+D - Application launcher
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
