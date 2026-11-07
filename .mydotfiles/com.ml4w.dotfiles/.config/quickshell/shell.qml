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