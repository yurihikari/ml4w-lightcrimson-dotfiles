hl.on("hyprland.start", function () 
    -- Start gnome keyring daemon
    hl.exec_cmd("gnome-keyring-daemon --daemonize --start --components=gpg,pkcs11,secrets,ssh")
    -- Allow root to access the X server for screenshots and other things that require elevated permissions
--    hl.exec_cmd("xhost +SI:localuser:root")
    -- Start tuxedo control center tray
--    hl.exec_cmd("tuxedo-control-center --tray")
    -- Start network manager applet
    hl.exec_cmd("nm-applet --indicator")
end)