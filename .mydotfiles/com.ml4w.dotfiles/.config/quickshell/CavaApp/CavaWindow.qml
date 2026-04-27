import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import qs.CustomTheme

PanelWindow {
    id: root

    // Layering
    WlrLayershell.layer: WlrLayer.Bottom
    exclusionMode: WlrLayershell.Ignore
    
    // Position
    anchors {
        left: true
        right: true
        bottom: true
    }
    height: 300
    
    // DEBUG: Keeping the red background as requested
    color: "transparent"

    // This is the data array
    property var barValues: []

    // --- CAVA PROCESS ---
    Process {
        id: cava
        running: true
        // Simplest possible command string
        command: ["bash", "-c", "cava -p <(echo -e '[output]\nmethod=raw\ndata_format=ascii\nascii_max_range=200\nbar_delimiter=32\nbars=200')"]
        
        stdout: SplitParser {
            // onRead is the standard signal. data is the string received.
            onRead: {
                var clean = data.trim();
                if (clean !== "") {
                    var parts = clean.split(/\s+/);
                    if (parts.length > 5) {
                        root.barValues = parts;
                    }
                }
            }
        }
    }

    // --- THE BARS ---
    Row {
        anchors.fill: parent
        spacing: 2

        Repeater {
            model: root.barValues
            Rectangle {
                // Ensure bars have a minimum width
                width: (root.width / 200) - 2
                // Ensure bars have a minimum height of 10px so you can see them
                height: Math.max(1, (parseInt(modelData) / 100) * root.height)
                anchors.bottom: parent.bottom
                
                // Using BLUE for high contrast against the RED box
                color: Theme.primary
                opacity: 0.6
                // Removed animation to prevent any performance hanging
            }
        }
    }

}