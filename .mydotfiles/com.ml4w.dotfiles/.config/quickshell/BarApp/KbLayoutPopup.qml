import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme
import qs.BarApp.services
import qs.BarApp.components

BarPopup {
    id: root
    ipcTarget: "bar-keyboard"
    keyboardFocusValue: active ? WlrLayershell.OnDemand : WlrLayershell.None

    Shortcut { sequence: "Escape"; onActivated: root.active = false }

    // Local state
    property string kbLayout: "US"
    property string kbVariant: ""
    property string searchText: ""
    property var allLayouts: []
    property var recentCodes: []   // "code:variant" strings, most-recent first
    property string customVariant: ""

    function flagFor(code) {
        let map = {
            "us": "🇺🇸", "gb": "🇬🇧", "fr": "🇫🇷", "de": "🇩🇪", "es": "🇪🇸",
            "it": "🇮🇹", "br": "🇧🇷", "pt": "🇵🇹", "ru": "🇷🇺", "ua": "🇺🇦",
            "pl": "🇵🇱", "cz": "🇨🇿", "se": "🇸🇪", "no": "🇳🇴", "fi": "🇫🇮",
            "dk": "🇩🇰", "nl": "🇳🇱", "be": "🇧🇪", "ch": "🇨🇭", "at": "🇦🇹",
            "gr": "🇬🇷", "tr": "🇹🇷", "jp": "🇯🇵", "kr": "🇰🇷", "cn": "🇨🇳",
            "in": "🇮🇳", "ca": "🇨🇦", "ro": "🇷🇴", "hu": "🇭🇺", "bg": "🇧🇬",
            "hr": "🇭🇷", "sk": "🇸🇰", "si": "🇸🇮", "lt": "🇱🇹", "lv": "🇱🇻",
            "ee": "🇪🇪", "is": "🇮🇸", "ie": "🇮🇪", "il": "🇮🇱", "ar": "🇸🇦",
            "th": "🇹🇭", "vn": "🇻🇳", "id": "🇮🇩", "my": "🇲🇾", "ph": "🇵🇭",
            "mx": "🇲🇽", "za": "🇿🇦", "by": "🇧🇾", "rs": "🇷🇸", "mk": "🇲🇰",
            "al": "🇦🇱", "ge": "🇬🇪", "am": "🇦🇲", "az": "🇦🇿", "kz": "🇰🇿",
            "ng": "🇳🇬", "ke": "🇰🇪", "ma": "🇲🇦"
        }
        return map[code] || "🌐"
    }

    function layoutByCode(code) {
        let lc = code.toLowerCase()
        for (let i = 0; i < allLayouts.length; i++)
            if (allLayouts[i].code === lc) return allLayouts[i]
        return { code: lc, name: code.toUpperCase(), variants: [] }
    }

    property var recentLayouts: {
        let out = []
        let curKey = kbLayout.toLowerCase() + ":" + kbVariant.toLowerCase()
        for (let i = 0; i < recentCodes.length; i++) {
            if (recentCodes[i].toLowerCase() !== curKey && out.length < 6) {
                let parts = recentCodes[i].split(":")
                let base = layoutByCode(parts[0])
                out.push({ code: parts[0], name: base.name, variant: parts[1] || "", variants: base.variants })
            }
        }
        return out
    }

    property var filtered: {
        if (searchText === "") return allLayouts
        let q = searchText.toLowerCase()
        return allLayouts.filter(function(l) {
            if (l.name.toLowerCase().includes(q) || l.code.toLowerCase().includes(q)) return true
            for (let i = 0; i < (l.variants ? l.variants.length : 0); i++) {
                if (l.variants[i].code.toLowerCase().includes(q) || l.variants[i].name.toLowerCase().includes(q))
                    return true
            }
            return false
        })
    }

    onOpened: {
        searchText = ""
        kbGetter.running = true
        cacheLoader.running = true
        recentLoader.running = true
    }

    Process {
        id: kbGetter
        command: ["bash", "-c", "l=$(grep -E 'kb_layout\\s*=' ~/.config/hypr/input.lua | cut -d'\"' -f2 | head -1); v=$(grep -E 'kb_variant\\s*=' ~/.config/hypr/input.lua | cut -d'\"' -f2 | head -1); echo \"${l:-US}|${v}\""]
        stdout: SplitParser {
            onRead: {
                let parts = data.trim().split("|")
                root.kbLayout = (parts[0] || "US").toUpperCase()
                root.kbVariant = parts[1] || ""
                // Pre-fill the custom variant input with whatever is currently set,
                // so manual edits to input.lua are reflected here too.
                root.customVariant = root.kbVariant
            }
        }
    }

    // ── CACHE LOADER ──
    Process {
        id: cacheLoader
        command: ["bash", "-c",
            "CACHE=\"$HOME/.cache/quickshell-kblayouts-v2.json\"; " +
            "if [ ! -s \"$CACHE\" ]; then " +
              "mkdir -p \"$(dirname \"$CACHE\")\"; " +
              "awk '" +
                "/! layout/   {sec=\"L\"; next} " +
                "/! variant/  {sec=\"V\"; next} " +
                "/^! /        {sec=\"\"; next} " +
                "sec==\"L\" && NF>=2 {code=$1; $1=\"\"; sub(/^ +/,\"\"); gsub(/\\\\/,\"\"); gsub(/\"/,\"\"); L[code]=$0; order[++n]=code} " +
                "sec==\"V\" && NF>=2 {vcode=$1; lay=$2; $1=\"\"; $2=\"\"; sub(/^ +/,\"\"); gsub(/\\\\/,\"\"); gsub(/\"/,\"\"); V[lay]=V[lay] (V[lay]?\"\\x1f\":\"\") vcode \"\\x1e\" $0} " +
                "END{ " +
                  "printf \"[\"; " +
                  "for(i=1;i<=n;i++){c=order[i]; " +
                    "printf \"%s{\\\"code\\\":\\\"%s\\\",\\\"name\\\":\\\"%s\\\",\\\"variants\\\":[\", (i>1?\",\":\"\"), c, L[c]; " +
                    "if(c in V){m=split(V[c],vv,\"\\x1f\"); for(j=1;j<=m;j++){split(vv[j],pp,\"\\x1e\"); printf \"%s{\\\"code\\\":\\\"%s\\\",\\\"name\\\":\\\"%s\\\"}\", (j>1?\",\":\"\"), pp[1], pp[2]}} " +
                    "printf \"]}\"} " +
                  "printf \"]\"}' /usr/share/X11/xkb/rules/evdev.lst > \"$CACHE\"; " +
            "fi; " +
            "cat \"$CACHE\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let arr = JSON.parse(text.trim())
                    root.allLayouts = arr.map(function(l) {
                        return { code: l.code, name: l.name, variants: l.variants || [] }
                    })
                } catch (e) {
                    console.log("kblayout cache parse error:", e)
                }
            }
        }
    }

    // ── RECENTS LOADER ──
    Process {
        id: recentLoader
        command: ["bash", "-c", "cat \"$HOME/.cache/quickshell-kbrecent-v2.json\" 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.recentCodes = JSON.parse(text.trim()) }
                catch (e) { root.recentCodes = [] }
            }
        }
    }

    function pushRecent(code, variant) {
        let key = code.toLowerCase() + ":" + (variant || "").toLowerCase()
        let arr = recentCodes.filter(function(c) { return c.toLowerCase() !== key })
        arr.unshift(key)
        arr = arr.slice(0, 8)
        recentCodes = arr
        let json = JSON.stringify(arr)
        Sys.run(["bash", "-c", "echo '" + json + "' > \"$HOME/.cache/quickshell-kbrecent-v2.json\""])
    }

    // Hyprland requires lowercase layout/variant — force it here.
    function applyLayout(code, variant) {
        let lc = (code || "").toLowerCase()
        let lv = (variant || "").toLowerCase()
        root.kbLayout = lc.toUpperCase()   // display stays uppercase
        root.kbVariant = lv
        pushRecent(lc, lv)
        let cmd = "sed -i -E 's/kb_layout\\s*=\\s*\".*\"/kb_layout  = \"'" + lc + "'\"/' ~/.config/hypr/input.lua && " +
                  "sed -i -E 's/kb_variant\\s*=\\s*\".*\"/kb_variant = \"'" + lv + "'\"/' ~/.config/hypr/input.lua && " +
                  "hyprctl reload"
        Sys.run(["bash", "-c", cmd])
        root.active = false
    }

    function editManually() {
        Sys.run(["bash", "-c", "kitty -e sh -c '${EDITOR:-nano} ~/.config/hypr/input.lua' >/dev/null 2>&1 &"])
        root.active = false
    }

    // Reusable box component
    component LayoutBox: Rectangle {
        id: lb
        property var layoutData
        property bool isCur: false
        property string curVariant: ""
        property bool expanded: false

        property var variants: layoutData.variants || []
        property bool hasVariants: variants.length > 0

        Layout.fillWidth: true
        Layout.preferredHeight: expanded ? (84 + variantFlow.implicitHeight + 12) : 84
        Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        radius: 14; clip: true

        color: isCur ? Theme.primary
                      : (bh.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                          : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05))
        border.color: isCur ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: bh.pressed ? 0.94 : (bh.containsMouse && !expanded ? 1.04 : 1.0)
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        // Header
        Column {
            id: head
            anchors.top: lb.expanded ? parent.top : undefined
            anchors.verticalCenter: lb.expanded ? undefined : parent.verticalCenter
            anchors.left: parent.left; anchors.right: parent.right
            anchors.topMargin: lb.expanded ? 10 : 0
            spacing: 3

            Text {
                text: root.flagFor(lb.layoutData.code); font.pixelSize: 22
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: lb.layoutData.code.toUpperCase()
                color: lb.isCur ? Theme.background : Theme.primary
                font.pixelSize: 12; font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 3
                Text {
                    text: lb.layoutData.name + (lb.isCur && lb.curVariant !== "" ? " (" + lb.curVariant + ")" : "")
                    color: lb.isCur ? Theme.background : Theme.primary
                    opacity: lb.isCur ? 0.9 : 0.5
                    font.pixelSize: 9; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                    width: Math.min(implicitWidth, lb.width - 30); maximumLineCount: 1
                }
                Text {
                    visible: lb.hasVariants
                    text: lb.expanded ? "󰅃" : "󰅀"
                    color: lb.isCur ? Theme.background : Theme.primary
                    opacity: 0.5; font.pixelSize: 9
                }
            }
        }

        Flow {
            id: variantFlow
            visible: lb.expanded
            anchors.top: head.bottom; anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: 6; anchors.rightMargin: 6; anchors.topMargin: 6
            spacing: 4

            Rectangle {
                height: 22; radius: 8; width: baseTxt.implicitWidth + 16
                property bool sel: lb.isCur && lb.curVariant === ""
                color: sel ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                Text {
                    id: baseTxt; anchors.centerIn: parent; text: "default"
                    color: sel ? Theme.background : Theme.primary; font.pixelSize: 9; font.bold: true
                }
                MouseArea { anchors.fill: parent; onClicked: root.applyLayout(lb.layoutData.code, "") }
            }

            Repeater {
                model: lb.variants
                delegate: Rectangle {
                    height: 22; radius: 8; width: vTxt.implicitWidth + 16
                    property bool sel: lb.isCur && lb.curVariant === modelData.code
                    color: sel ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                    Text {
                        id: vTxt; anchors.centerIn: parent; text: modelData.code
                        color: sel ? Theme.background : Theme.primary; font.pixelSize: 9; font.bold: true
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.applyLayout(lb.layoutData.code, modelData.code) }
                }
            }
        }

        MouseArea {
            id: bh
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 92
            hoverEnabled: true
            onClicked: {
                if (lb.hasVariants) lb.expanded = !lb.expanded
                else root.applyLayout(lb.layoutData.code, "")
            }
        }
    }

    Item {
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: 45; anchors.rightMargin: 230
        width: 420; height: 660

        transformOrigin: Item.Top
        opacity: root.active ? 1.0 : 0.0
        scale: root.active ? 1.0 : 0.95
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic; onRunningChanged: if(!running && !root.active) root.isAnimating = false } }
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

        Shadow { radius: 24 }

        Rectangle { anchors.fill: parent; radius: 24; color: Theme.background; opacity: 0.8 }

        Rectangle {
            anchors.fill: parent; radius: 24; color: "transparent"
            border.color: Theme.withAlpha(Theme.primary, 0.8); border.width: 2
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 14

                // Header
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Text { text: "󰌌"; color: Theme.primary; font.pixelSize: 20 }
                    Text { text: "Keyboard Layout"; color: Theme.primary; font.pixelSize: 16; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Text { text: root.filtered.length + " layouts"; color: Theme.primary; opacity: 0.4; font.pixelSize: 11; font.bold: true }
                }

                // Search box
                Rectangle {
                    Layout.fillWidth: true; height: 40; radius: 12
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                    border.color: searchInput.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                    border.width: searchInput.activeFocus ? 2 : 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 8
                        Text { text: "󰍉"; color: Theme.primary; opacity: 0.5; font.pixelSize: 16 }
                        TextField {
                            id: searchInput; Layout.fillWidth: true
                            placeholderText: "Search layouts…"
                            color: Theme.primary
                            placeholderTextColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                            font.pixelSize: 14; background: null
                            onTextChanged: root.searchText = text
                            verticalAlignment: TextInput.AlignVCenter
                        }
                    }
                }

                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width; contentHeight: contentCol.implicitHeight

                    ColumnLayout {
                        id: contentCol
                        width: parent.width; spacing: 12

                        // CURRENT
                        Text {
                            text: "CURRENT"; color: Theme.primary; font.pixelSize: 10; font.bold: true; opacity: 0.4
                            visible: root.searchText === ""
                        }
                        LayoutBox {
                            visible: root.searchText === ""
                            Layout.fillWidth: true
                            layoutData: root.layoutByCode(root.kbLayout)
                            isCur: true
                            curVariant: root.kbVariant
                        }

                        // CUSTOM VARIANT BUILDER
                        Text {
                            text: "CUSTOM VARIANT"; color: Theme.primary; font.pixelSize: 10; font.bold: true; opacity: 0.4
                            visible: root.searchText === ""
                        }
                        RowLayout {
                            visible: root.searchText === ""
                            Layout.fillWidth: true; spacing: 8

                            Rectangle {
                                Layout.fillWidth: true; height: 38; radius: 10
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                                border.color: varInput.activeFocus ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                                border.width: varInput.activeFocus ? 2 : 1
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 6
                                    Text {
                                        text: root.kbLayout.toLowerCase() + " /"
                                        color: Theme.primary; opacity: 0.5; font.pixelSize: 12; font.bold: true
                                    }
                                    TextField {
                                        id: varInput; Layout.fillWidth: true
                                        placeholderText: "variant e.g. intl, dvorak"
                                        text: root.customVariant
                                        color: Theme.primary
                                        placeholderTextColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                                        font.pixelSize: 13; background: null
                                        onTextChanged: if (text !== root.customVariant) root.customVariant = text
                                        verticalAlignment: TextInput.AlignVCenter
                                        Keys.onReturnPressed: if (text.trim() !== "") root.applyLayout(root.kbLayout, text.trim())
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 64; height: 38; radius: 10
                                property bool enabled: root.customVariant.trim() !== ""
                                color: enabled ? (applyHover.containsMouse ? Qt.lighter(Theme.primary, 1.1) : Theme.primary)
                                                : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    anchors.centerIn: parent; text: "Apply"
                                    color: parent.enabled ? Theme.background : Theme.primary
                                    opacity: parent.enabled ? 1.0 : 0.4
                                    font.pixelSize: 12; font.bold: true
                                }
                                MouseArea {
                                    id: applyHover; anchors.fill: parent; hoverEnabled: true
                                    onClicked: if (parent.enabled) root.applyLayout(root.kbLayout, root.customVariant.trim())
                                }
                            }
                        }
                        Text {
                            visible: root.searchText === ""
                            text: "Creates " + root.kbLayout.toLowerCase() + " (" + (root.customVariant.trim() || "…") + ") using the current layout"
                            color: Theme.primary; opacity: 0.35; font.pixelSize: 9; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        }

                        // RECENT
                        Text {
                            text: "RECENT"; color: Theme.primary; font.pixelSize: 10; font.bold: true; opacity: 0.4
                            visible: root.searchText === "" && root.recentLayouts.length > 0
                        }
                        GridLayout {
                            visible: root.searchText === "" && root.recentLayouts.length > 0
                            Layout.fillWidth: true
                            columns: 3; columnSpacing: 8; rowSpacing: 8
                            Repeater {
                                model: root.recentLayouts
                                delegate: LayoutBox {
                                    layoutData: modelData
                                    isCur: root.kbLayout === modelData.code.toUpperCase() && root.kbVariant === (modelData.variant || "")
                                    curVariant: modelData.variant || ""
                                }
                            }
                        }

                        // ALL
                        Text {
                            text: root.searchText === "" ? "ALL LAYOUTS" : "RESULTS"
                            color: Theme.primary; font.pixelSize: 10; font.bold: true; opacity: 0.4
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3; columnSpacing: 8; rowSpacing: 8
                            Repeater {
                                model: root.filtered
                                delegate: LayoutBox {
                                    layoutData: modelData
                                    isCur: root.kbLayout === modelData.code.toUpperCase()
                                    curVariant: root.kbVariant
                                }
                            }
                        }
                    }
                }

                // FOOTER — edit file manually
                Rectangle {
                    Layout.fillWidth: true; height: 40; radius: 12
                    color: editHover.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                                   : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2); border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    RowLayout {
                        anchors.centerIn: parent; spacing: 8
                        Text { text: "󰷈"; color: Theme.primary; font.pixelSize: 15 }
                        Text { text: "Edit input.lua manually"; color: Theme.primary; font.pixelSize: 12; font.bold: true }
                    }
                    MouseArea { id: editHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.editManually() }
                }
            }
        }
    }
}