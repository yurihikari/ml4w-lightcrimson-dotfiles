import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../CustomTheme"

PanelWindow {
    id: root
    property bool active: false
    property bool isAnimating: false
    visible: active || isAnimating

    // --- IPC HANDLER ---
    IpcHandler {
        target: "display"
        function open(): void { root.active = true }
        function close(): void { root.active = false }
        function toggle(): void { root.active = !root.active }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: active ? WlrLayershell.OnDemand : WlrLayershell.None
    color: "transparent"

    MouseArea { anchors.fill: parent; onClicked: root.active = false }
    Shortcut { sequence: "Escape"; onActivated: root.active = false }

    // ─── STATE ───────────────────────────────────────────────────────────
    property int selectedIndex: 0
    property bool isLoading: true

    // Visual Map scaling state
    property real mapScale: 1.0
    property real mapOffsetX: 0
    property real mapOffsetY: 0
    property real mapMinX: 0
    property real mapMinY: 0

    // Drag state
    property int snapThreshold: 30 // pixels (logical) for edge-snapping

    ListModel { id: monitorModel }
    ListModel { id: currentModesList }

    onActiveChanged: {
        if (active) {
            isAnimating = true
            root.isLoading = true
            loadMonitors.running = true
        }
    }

    onSelectedIndexChanged: updateModeList()

    function updateModeList() {
        currentModesList.clear()
        if (monitorModel.count > 0 && selectedIndex >= 0 && selectedIndex < monitorModel.count) {
            let m = monitorModel.get(selectedIndex)
            let modes = m.modesStr.split(",")
            for (let i = 0; i < modes.length; i++) {
                if (modes[i].trim() !== "") {
                    currentModesList.append({ text: modes[i] })
                }
            }
        }
    }

    function logicalSize(m) {
        let w = m.mWidth / m.mScale
        let h = m.mHeight / m.mScale
        if (m.mTransform === 1 || m.mTransform === 3) { let t = w; w = h; h = t }
        return { w: w, h: h }
    }

    function updateMap() {
        if (monitorModel.count === 0) return
        let minX = 999999, minY = 999999, maxX = -999999, maxY = -999999
        let hasActive = false

        for (let i = 0; i < monitorModel.count; i++) {
            let m = monitorModel.get(i)
            if (m.disabled) continue
            hasActive = true
            let s = logicalSize(m)
            if (m.mX < minX) minX = m.mX
            if (m.mY < minY) minY = m.mY
            if (m.mX + s.w > maxX) maxX = m.mX + s.w
            if (m.mY + s.h > maxY) maxY = m.mY + s.h
        }

        if (!hasActive) return
        if (minX === 999999) minX = 0
        if (minY === 999999) minY = 0

        let totalW = maxX - minX
        let totalH = maxY - minY

        let availableW = mapArea.width - 80
        let availableH = mapArea.height - 80

        let scaleX = availableW / (totalW || 1)
        let scaleY = availableH / (totalH || 1)

        root.mapScale = Math.min(scaleX, scaleY)
        root.mapOffsetX = (mapArea.width - (totalW * root.mapScale)) / 2
        root.mapOffsetY = (mapArea.height - (totalH * root.mapScale)) / 2
        root.mapMinX = minX
        root.mapMinY = minY
    }

    // Convert pixel position inside the map back to logical monitor coordinates
    function pixelToLogical(px, py) {
        return {
            x: Math.round((px - root.mapOffsetX) / root.mapScale + root.mapMinX),
            y: Math.round((py - root.mapOffsetY) / root.mapScale + root.mapMinY)
        }
    }

    // Snap a monitor's edges to other monitors' edges
    function snapPosition(idx, newX, newY) {
        let m = monitorModel.get(idx)
        let s = logicalSize(m)
        let threshold = root.snapThreshold

        let snappedX = newX
        let snappedY = newY

        for (let i = 0; i < monitorModel.count; i++) {
            if (i === idx) continue
            let other = monitorModel.get(i)
            if (other.disabled) continue
            let os = logicalSize(other)

            // Horizontal snapping (X axis)
            // Left edge to other's right edge
            if (Math.abs(newX - (other.mX + os.w)) < threshold) snappedX = other.mX + os.w
            // Right edge to other's left edge
            else if (Math.abs((newX + s.w) - other.mX) < threshold) snappedX = other.mX - s.w
            // Left edge to other's left edge
            else if (Math.abs(newX - other.mX) < threshold) snappedX = other.mX
            // Right edge to other's right edge
            else if (Math.abs((newX + s.w) - (other.mX + os.w)) < threshold) snappedX = other.mX + os.w - s.w

            // Vertical snapping (Y axis)
            if (Math.abs(newY - (other.mY + os.h)) < threshold) snappedY = other.mY + os.h
            else if (Math.abs((newY + s.h) - other.mY) < threshold) snappedY = other.mY - s.h
            else if (Math.abs(newY - other.mY) < threshold) snappedY = other.mY
            else if (Math.abs((newY + s.h) - (other.mY + os.h)) < threshold) snappedY = other.mY + os.h - s.h
        }
        return { x: snappedX, y: snappedY }
    }

    // ─── PROCESSES ───────────────────────────────────────────────────────
    Process {
        id: loadMonitors
        property string _jsonBuf: ""
        command: ["bash", "-c", "hyprctl monitors all -j"]
        stdout: SplitParser { onRead: { loadMonitors._jsonBuf += data + "\n" } }
        onRunningChanged: {
            if (!running) {
                try {
                    if (loadMonitors._jsonBuf.trim() !== "") {
                        let parsedData = JSON.parse(loadMonitors._jsonBuf)
                        monitorModel.clear()

                        for (let i = 0; i < parsedData.length; i++) {
                            let m = parsedData[i]
                            let currentMode = m.width + "x" + m.height + "@" + parseFloat(m.refreshRate).toFixed(2)
                            let modesArr = []
                            if (m.availableModes && m.availableModes.length > 0) {
                                for (let j = 0; j < m.availableModes.length; j++) {
                                    modesArr.push(m.availableModes[j].replace("Hz", "").trim())
                                }
                            } else {
                                modesArr.push(currentMode)
                            }

                            monitorModel.append({
                                name: m.name || "Unknown",
                                description: m.description || m.model || "Unknown Display",
                                disabled: m.disabled === true,
                                modeStr: currentMode,
                                mWidth: m.width || 1920,
                                mHeight: m.height || 1080,
                                mX: m.x || 0,
                                mY: m.y || 0,
                                mScale: m.scale || 1.0,
                                mTransform: m.transform || 0,
                                modesStr: modesArr.join(",")
                            })
                        }
                    }
                } catch(e) {
                    console.log("Error parsing hyprctl monitors: " + e)
                }

                root.isLoading = false
                loadMonitors._jsonBuf = ""
                root.selectedIndex = 0
                root.updateModeList()
                root.updateMap()
            }
        }
    }

    Process { id: saveProc }

    function applyAndSave() {
        let luaCode = "-- Generated by Quickshell Display Manager\n\n"

        for (let i = 0; i < monitorModel.count; i++) {
            let m = monitorModel.get(i)

            if (m.disabled) {
                luaCode += "hl.monitor({\n"
                luaCode += "    output = \"" + m.name + "\",\n"
                luaCode += "    mode = \"disable\"\n"
                luaCode += "})\n\n"
            } else {
                luaCode += "hl.monitor({\n"
                luaCode += "    output = \"" + m.name + "\",\n"
                luaCode += "    mode = \"" + m.modeStr + "\",\n"
                luaCode += "    position = \"" + m.mX + "x" + m.mY + "\",\n"
                luaCode += "    scale = " + parseFloat(m.mScale).toFixed(2) + ",\n"
                if (m.mTransform !== 0) {
                    luaCode += "    transform = " + m.mTransform + "\n"
                }
                luaCode += "})\n\n"
            }
        }

        let b64 = Qt.btoa(unescape(encodeURIComponent(luaCode)))
        let path = "$HOME/.mydotfiles/com.ml4w.dotfiles/.config/hypr/monitors.lua"

        saveProc.command = [
            "bash", "-c",
            "mkdir -p $(dirname " + path + ") && " +
            "echo '" + b64 + "' | base64 -d > " + path + " && " +
            "hyprctl reload"
        ]
        saveProc.running = true
        root.active = false
    }

    // ─── REUSABLE COMPONENTS ─────────────────────────────────────────────
    // FIXED: explicit ids on label/input, no `parent.parent` chains that break under GridLayout reparenting
    component GlassInput: Rectangle {
        id: glass
        property string label: ""
        property string valueText: ""
        signal edited(string text)

        // Without these, GridLayout collapses this cell when a sibling
        // (like ComboBox) reports a larger implicitWidth in the same column.
        implicitWidth: 200
        implicitHeight: 44
        Layout.fillWidth: true
        Layout.minimumWidth: 180
        Layout.preferredHeight: 44
        radius: 12
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Text {
                id: lblText
                text: glass.label
                color: Theme.primary
                font.bold: true
                font.pixelSize: 11
                opacity: 0.5
                Layout.preferredWidth: 60
            }
            TextInput {
                id: inputField
                Layout.fillWidth: true
                text: glass.valueText
                color: Theme.primary
                font.pixelSize: 14
                font.bold: true
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true
                onTextEdited: glass.edited(text)
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // MAIN UI LAYOUT
    // ══════════════════════════════════════════════════════════════════════════
    Rectangle {
        width: 1200
        height: 800
        anchors.centerIn: parent

        opacity: root.active ? 1.0 : 0.0
        scale: root.active ? 1.0 : 0.95
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic; onRunningChanged: if (!running && !root.active) root.isAnimating = false } }
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

        color: "transparent"
        radius: 30

        Rectangle {
            anchors.fill: parent; radius: 30
            color: Theme.background; opacity: 0.9
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8); border.width: 2
        }

        MouseArea { anchors.fill: parent } // Eat clicks

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 0

            // ── HEADER ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                spacing: 14

                Rectangle {
                    width: 40; height: 40; radius: 12
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                    Text { anchors.centerIn: parent; text: "󰍹"; color: Theme.primary; font.pixelSize: 20 }
                }

                ColumnLayout {
                    spacing: 2
                    Text { text: "Display Manager"; color: Theme.primary; font.pixelSize: 18; font.bold: true }
                    Text { text: "Drag monitors to reposition · Manage Hyprland configuration"; color: Theme.primary; font.pixelSize: 12; opacity: 0.5 }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 36; height: 36; radius: 18
                    color: closeMouse.containsMouse ? Qt.rgba(255, 100, 100, 0.15) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                    Text { anchors.centerIn: parent; text: "󰅖"; color: closeMouse.containsMouse ? "#ff6b6b" : Theme.primary; font.pixelSize: 16; opacity: 0.8 }
                    MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.active = false }
                }
            }

            Item { Layout.preferredHeight: 16 }

            // ── VISUAL MAP AREA ──
            Rectangle {
                id: mapArea
                Layout.fillWidth: true
                Layout.preferredHeight: 300
                radius: 16
                color: Qt.rgba(0, 0, 0, 0.15)
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                border.width: 1
                clip: true

                onWidthChanged: root.updateMap()
                onHeightChanged: root.updateMap()

                Text {
                    anchors.centerIn: parent
                    text: root.isLoading ? "Loading..." : "Displays disabled or unavailable"
                    color: Theme.primary; opacity: 0.3
                    visible: root.isLoading || monitorModel.count === 0
                }

                Repeater {
                    model: monitorModel
                    delegate: Rectangle {
                        id: monRect
                        property bool isSel: root.selectedIndex === index
                        property real logicalW: {
                            let w = model.mWidth / model.mScale
                            let h = model.mHeight / model.mScale
                            return (model.mTransform === 1 || model.mTransform === 3) ? h : w
                        }
                        property real logicalH: {
                            let w = model.mWidth / model.mScale
                            let h = model.mHeight / model.mScale
                            return (model.mTransform === 1 || model.mTransform === 3) ? w : h
                        }
                        property bool dragging: false

                        visible: !model.disabled

                        // Position: when not dragging, derive from model; when dragging, leave alone
                        Binding on x {
                            when: !monRect.dragging
                            value: root.mapOffsetX + ((model.mX - root.mapMinX) * root.mapScale)
                        }
                        Binding on y {
                            when: !monRect.dragging
                            value: root.mapOffsetY + ((model.mY - root.mapMinY) * root.mapScale)
                        }

                        width: logicalW * root.mapScale
                        height: logicalH * root.mapScale

                        color: isSel ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.8)
                                     : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                        border.color: isSel ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                        border.width: isSel ? 2 : 1
                        radius: 4

                        Behavior on color { ColorAnimation { duration: 150 } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: model.name
                                color: monRect.isSel ? Theme.background : Theme.primary
                                font.pixelSize: 16; font.bold: true
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: model.mX + ", " + model.mY
                                color: monRect.isSel ? Theme.background : Theme.primary
                                opacity: 0.7
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: monRect.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            property real pressX: 0
                            property real pressY: 0
                            property real startMonX: 0
                            property real startMonY: 0
                            property bool didDrag: false

                            onPressed: (mouse) => {
                                root.selectedIndex = index
                                pressX = mouse.x
                                pressY = mouse.y
                                startMonX = monRect.x
                                startMonY = monRect.y
                                didDrag = false
                            }

                            onPositionChanged: (mouse) => {
                                if (!pressed) return
                                let dx = mouse.x - pressX
                                let dy = mouse.y - pressY
                                if (!didDrag && (Math.abs(dx) > 3 || Math.abs(dy) > 3)) {
                                    didDrag = true
                                    monRect.dragging = true
                                }
                                if (monRect.dragging) {
                                    // Update visual position
                                    let newPxX = startMonX + dx
                                    let newPxY = startMonY + dy
                                    monRect.x = newPxX
                                    monRect.y = newPxY

                                    // Live preview of logical coords (no snap during drag motion to keep it smooth)
                                    let logical = root.pixelToLogical(newPxX, newPxY)
                                    monitorModel.setProperty(index, "mX", logical.x)
                                    monitorModel.setProperty(index, "mY", logical.y)
                                }
                            }

                            onReleased: {
                                if (monRect.dragging) {
                                    // Snap to neighbours on release
                                    let m = monitorModel.get(index)
                                    let snapped = root.snapPosition(index, m.mX, m.mY)
                                    monitorModel.setProperty(index, "mX", snapped.x)
                                    monitorModel.setProperty(index, "mY", snapped.y)
                                    monRect.dragging = false
                                    root.updateMap()
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 16 }

            // ── TAB SELECTOR ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: monitorModel
                    delegate: Rectangle {
                        property bool isSel: root.selectedIndex === index
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: tabLbl.implicitWidth + 36
                        radius: 18

                        color: isSel ? Theme.primary
                                     : (tabMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : "transparent")
                        border.color: isSel ? "transparent" : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent; spacing: 6
                            Rectangle { width: 8; height: 8; radius: 4; color: model.disabled ? "#ff5555" : "#50fa7b"; opacity: isSel ? 1.0 : 0.6 }
                            Text { id: tabLbl; text: model.name; color: isSel ? Theme.background : Theme.primary; font.pixelSize: 13; font.bold: isSel }
                        }

                        MouseArea {
                            id: tabMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: { root.selectedIndex = index; root.updateMap() }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 10 }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }
            Item { Layout.preferredHeight: 14 }

            // ── SETTINGS FOR SELECTED MONITOR ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    visible: monitorModel.count > 0 && !root.isLoading
                    spacing: 14

                    // Name and Enable Toggle
                    RowLayout {
                        Layout.fillWidth: true

                        ColumnLayout {
                            spacing: 2; Layout.fillWidth: true
                            Text {
                                text: monitorModel.count > 0 ? monitorModel.get(root.selectedIndex).name : ""
                                color: Theme.primary; font.pixelSize: 18; font.bold: true
                            }
                            Text {
                                text: monitorModel.count > 0 ? monitorModel.get(root.selectedIndex).description : ""
                                color: Theme.primary; opacity: 0.5; font.pixelSize: 12
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 130; Layout.preferredHeight: 40; radius: 12
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15); border.width: 1
                            RowLayout {
                                anchors.centerIn: parent; spacing: 8
                                Text {
                                    text: monitorModel.count > 0 && !monitorModel.get(root.selectedIndex).disabled ? "Active" : "Disabled"
                                    color: Theme.primary; opacity: 0.8; font.pixelSize: 12; font.bold: true
                                }
                                Rectangle {
                                    width: 36; height: 20; radius: 10
                                    color: monitorModel.count > 0 && !monitorModel.get(root.selectedIndex).disabled
                                           ? Theme.primary
                                           : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                                    Rectangle {
                                        width: 14; height: 14; radius: 7; y: 3
                                        x: monitorModel.count > 0 && !monitorModel.get(root.selectedIndex).disabled ? 19 : 3
                                        color: Theme.background
                                        Behavior on x { NumberAnimation { duration: 150 } }
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (monitorModel.count > 0) {
                                        let disabled = monitorModel.get(root.selectedIndex).disabled
                                        monitorModel.setProperty(root.selectedIndex, "disabled", !disabled)
                                        root.updateMap()
                                    }
                                }
                            }
                        }
                    }

                    // Dense Controls Grid
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 20
                        rowSpacing: 12
                        opacity: monitorModel.count > 0 && !monitorModel.get(root.selectedIndex).disabled ? 1.0 : 0.4

                        GlassInput {
                            label: "Pos X:"
                            valueText: monitorModel.count > 0 ? monitorModel.get(root.selectedIndex).mX.toString() : "0"
                            onEdited: (text) => {
                                monitorModel.setProperty(root.selectedIndex, "mX", parseInt(text) || 0)
                                root.updateMap()
                            }
                        }

                        GlassInput {
                            label: "Pos Y:"
                            valueText: monitorModel.count > 0 ? monitorModel.get(root.selectedIndex).mY.toString() : "0"
                            onEdited: (text) => {
                                monitorModel.setProperty(root.selectedIndex, "mY", parseInt(text) || 0)
                                root.updateMap()
                            }
                        }

                        GlassInput {
                            label: "Scale:"
                            valueText: monitorModel.count > 0 ? parseFloat(monitorModel.get(root.selectedIndex).mScale).toFixed(2) : "1.00"
                            onEdited: (text) => {
                                monitorModel.setProperty(root.selectedIndex, "mScale", parseFloat(text) || 1.0)
                                root.updateMap()
                            }
                        }

                        // Native ComboBox for Modes
                        ComboBox {
                            id: modeCombo
                            implicitWidth: 200
                            Layout.fillWidth: true
                            Layout.minimumWidth: 180
                            Layout.preferredHeight: 44
                            model: currentModesList
                            textRole: "text"

                            currentIndex: {
                                if (monitorModel.count === 0) return -1
                                let target = monitorModel.get(root.selectedIndex).modeStr
                                for (let i = 0; i < currentModesList.count; i++) {
                                    if (currentModesList.get(i).text === target) return i
                                }
                                return 0
                            }

                            onActivated: (index) => {
                                if (monitorModel.count > 0) {
                                    let newMode = currentModesList.get(index).text
                                    monitorModel.setProperty(root.selectedIndex, "modeStr", newMode)
                                    let res = newMode.split("@")[0].split("x")
                                    if (res.length === 2) {
                                        monitorModel.setProperty(root.selectedIndex, "mWidth", parseInt(res[0]))
                                        monitorModel.setProperty(root.selectedIndex, "mHeight", parseInt(res[1]))
                                        root.updateMap()
                                    }
                                }
                            }

                            background: Rectangle {
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                border.width: 1; radius: 12
                            }
                            contentItem: Text {
                                text: "Mode:   " + modeCombo.currentText
                                color: Theme.primary; font.pixelSize: 13; font.bold: true
                                verticalAlignment: Text.AlignVCenter; leftPadding: 12
                            }
                        }

                        // Transform Selection Row
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.columnSpan: 2
                            Layout.preferredHeight: 44
                            radius: 12
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent; anchors.margins: 4; spacing: 4
                                Text {
                                    text: "Rotation:"
                                    color: Theme.primary; font.bold: true; font.pixelSize: 11; opacity: 0.5
                                    Layout.leftMargin: 8; Layout.preferredWidth: 60
                                }

                                Repeater {
                                    model: [
                                        { val: 0, label: "Normal" },
                                        { val: 1, label: "90°" },
                                        { val: 2, label: "180°" },
                                        { val: 3, label: "270°" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool isCur: monitorModel.count > 0 && monitorModel.get(root.selectedIndex).mTransform === modelData.val
                                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 8
                                        color: isCur ? Theme.primary
                                                     : (rotMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : "transparent")

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: parent.isCur ? Theme.background : Theme.primary
                                            font.pixelSize: 12; font.bold: parent.isCur
                                        }
                                        MouseArea {
                                            id: rotMouse; anchors.fill: parent; hoverEnabled: true
                                            onClicked: {
                                                monitorModel.setProperty(root.selectedIndex, "mTransform", modelData.val)
                                                root.updateMap()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // ── APPLY BUTTON ──
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        radius: 16
                        color: applyMouse.containsMouse
                               ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                               : Theme.primary
                        scale: applyMouse.pressed ? 0.98 : 1.0
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 150 } }

                        RowLayout {
                            anchors.centerIn: parent; spacing: 10
                            Text { text: "󰆓"; color: Theme.background; font.pixelSize: 20 }
                            Text { text: "Apply & Save to config"; color: Theme.background; font.pixelSize: 15; font.bold: true }
                        }
                        MouseArea {
                            id: applyMouse; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.applyAndSave()
                        }
                    }
                }
            }
        }
    }
}
