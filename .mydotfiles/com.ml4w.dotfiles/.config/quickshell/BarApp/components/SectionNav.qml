import QtQuick
import qs.CustomTheme
import qs.BarApp.services

// Small switcher shown in the header of each right-hand section (keyboard,
// clipboard, notifications, calendar, system). It ties them together as sections of one panel:
// picking another one opens that popup, and the shared popout morphs to it,
// just like clicking its icon in the bar.
Row {
    id: root
    // The PopoutHost (a popup's `host`) and the ipcTarget of the section shown.
    property var host: null
    property string current: ""

    readonly property var sections: [
        { target: "bar-keyboard",  icon: "󰌌", name: "Keyboard" },
        { target: "bar-clipboard", icon: "󰅌", name: "Clipboard" },
        { target: "bar-notifications", icon: "󰂚", name: "Notifications" },
        { target: "bar-calendar",  icon: "󰃭", name: "Calendar" },
        { target: "bar-system",    icon: "󰤨", name: "System" }
    ]

    function openSection(target) {
        if (!host || target === current) return
        for (const p of host.popups) {
            if (p.ipcTarget === target) { p.active = true; return }
        }
    }

    spacing: 2

    Repeater {
        model: root.sections
        Rectangle {
            required property var modelData
            readonly property bool isCurrent: modelData.target === root.current
            width: 30; height: 30
            radius: 9
            color: isCurrent ? Theme.withAlpha(Theme.primary, 0.16)
                 : (navMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.08) : "transparent")
            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: parent.modelData.icon
                color: Theme.primary
                font.pixelSize: 15
                opacity: parent.isCurrent ? 1.0 : (navMouse.containsMouse ? 0.8 : 0.45)
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            MouseArea {
                id: navMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSection(parent.modelData.target)
            }
        }
    }
}
