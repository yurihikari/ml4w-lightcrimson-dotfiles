//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import QtQuick
import "WelcomeApp"
import "SidebarApp"
import "WallpaperApp"
import "WorkspaceWallpaperAPP"
import "StatusbarApp"
import "CustomTheme"
import "CavaApp"
import "BarApp"
import "RadialMenuApp"
import "DisplayManagerApp"
import "SettingsApp"

ShellRoot {
    // Test IPC tools: qs ipc show

    // Load the saved palette (colors.json) every time the shell loads,
    // including Quickshell's hot reload after a config file changes: the
    // Theme singleton is rebuilt with its built-in defaults then, and nothing
    // else would ask it to read the file again.
    Component.onCompleted: Theme.reloadTheme()

    IpcHandler {
        target: "theme-manager"
        function reload(): void {
            Theme.reloadTheme()
        }
    }

    // The bar lives inside the screen frame (ScreenFrame draws frame + bar as
    // one surface and hosts the bar's content).
    Variants {
        model: Quickshell.screens
        delegate: Component {
            ScreenFrame {}
        }
    }
    WelcomeWindow {}
    SidebarWindow {}
    WallpaperWindow {}
    WallpaperCarousel {}
    WorkspaceWallpaperWindow {}
    RadialMenuPopup {}
    DisplayManagerWindow { id: displayManager }
    SettingsLauncher {}
    // Variants {
    //     model: Quickshell.screens
    //     delegate: Component {
    //         CavaWindow {}
    //     }
    // }
    StatusbarWindow {}
}