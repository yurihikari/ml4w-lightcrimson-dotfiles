hl.on("hyprland.start", function () 
    -- Start gnome keyring daemon
    hl.exec_cmd("gnome-keyring-daemon --daemonize --start --components=gpg,pkcs11,secrets,ssh")
    -- Allow root to access the X server for screenshots and other things that require elevated permissions
    hl.exec_cmd("xhost +SI:localuser:root")
    -- Start tuxedo control center tray
    hl.exec_cmd("tuxedo-control-center --tray")
    -- Start network manager applet
    hl.exec_cmd("nm-applet --indicator")
    -- Start xdg-desktop-portal-hyprland for screen capture and other portal features
    hl.exec_cmd("/usr/lib/xdg-desktop-portal-hyprland")
    hl.exec_cmd("/usr/lib/xdg-desktop-portal")
    -- Start per-workspace wallpaper manager after ML4W wallpaper init
    hl.exec_cmd("bash -c 'sleep 2; setsid nohup ~/.config/hypr/conf/custom/workspace-wallpapers.sh >> ~/.cache/workspace-wallpapers.log 2>&1 &'")
end)