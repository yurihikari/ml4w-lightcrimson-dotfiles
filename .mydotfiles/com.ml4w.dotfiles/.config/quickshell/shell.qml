import Quickshell
import Quickshell.Io
import QtQuick
import "WelcomeApp"
import "PowerApp"
import "SidebarApp"
import "CalendarApp"
import "WallpaperApp"
import "CustomTheme"
import "CavaApp"
import "BarApp"
import "RadialMenuApp"
import "DisplayManagerApp"

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
    RadialMenuPopup {}
    DisplayManagerWindow { id: displayManager }
    // Variants {
    //     model: Quickshell.screens
    //     delegate: Component {
    //         CavaWindow {}
    //     }
    // }
}