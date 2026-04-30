import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import qs.CustomTheme

PanelWindow {
    id: root
    property var modelData
    screen: modelData
    WlrLayershell.layer: WlrLayer.Bottom
    exclusionMode: WlrLayershell.Ignore
    
    anchors {
        left: true
        right: true
        bottom: true
    }
    height: 300
    color: "transparent"

    // Use a simple array to store heights
    property var rawData: []

    Process {
        id: cava
        running: true
        command: ["bash", "-c", "cava -p <(echo -e '[output]\nmethod=raw\ndata_format=ascii\nascii_max_range=200\nbar_delimiter=32\nbars=200')"]
        
        stdout: SplitParser {
            onRead: {
                var clean = data.trim();
                if (clean.length > 0) {
                    var parts = clean.split(/\s+/);
                    if (parts.length >= 200) {
                        root.rawData = parts;
                        canvas.requestPaint(); // Trigger a redraw
                    }
                }
            }
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        // Smoothing makes it look better, but 'fast' is better for performance
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            
            var barCount = 200;
            var spacing = 2;
            var barWidth = (width / barCount) - spacing;
            
            // Use the primary theme color
            ctx.fillStyle = Theme.primary;
            ctx.globalAlpha = 0.6;

            for (var i = 0; i < barCount; i++) {
                var val = parseInt(root.rawData[i]) || 0;
                // Calculate height: (val / max_range) * total_height
                var barHeight = (val / 200) * height;
                
                // Draw from bottom up
                ctx.fillRect(
                    i * (barWidth + spacing), 
                    height - barHeight, 
                    barWidth, 
                    barHeight
                );
            }
        }
    }
}