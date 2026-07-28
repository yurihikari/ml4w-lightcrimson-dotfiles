//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import QtQuick
import "WelcomeApp"
import "PowerApp"
import "SidebarApp"
import "CalendarApp"
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

    Variants {
        model: Quickshell.screens
        delegate: Component {
            MainBar {}
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: Component {
            ScreenFrame {}
        }
    }
    WelcomeWindow {}
    PowerWindow {}
    SidebarWindow {}
    CalendarWindow {}
    WallpaperWindow {}
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