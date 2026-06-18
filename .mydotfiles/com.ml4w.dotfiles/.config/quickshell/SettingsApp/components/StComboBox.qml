import QtQuick
import QtQuick.Controls
import qs.CustomTheme

// Themed dropdown. Use like a normal ComboBox (model, textRole, currentIndex,
// onActivated). Styling matches the rest of the shell.
ComboBox {
    id: control
    implicitWidth: 200
    implicitHeight: 38

    delegate: ItemDelegate {
        id: itemDelegate
        width: control.width
        highlighted: control.highlightedIndex === index

        // Robust label resolution: works for plain string arrays AND arrays of
        // objects with a textRole, without ever resolving to undefined/blank.
        readonly property string label: {
            var r = control.textRole
            if (r && r.length > 0) {
                if (modelData !== undefined && modelData !== null && modelData[r] !== undefined) return modelData[r]
                if (typeof model !== "undefined" && model !== null && model[r] !== undefined) return model[r]
                return ""
            }
            if (modelData !== undefined && modelData !== null) return "" + modelData
            return ""
        }

        contentItem: Text {
            text: itemDelegate.label
            color: itemDelegate.highlighted ? Theme.background : Theme.primary
            font.family: Theme.fontFamily
            font.pixelSize: 13
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            color: itemDelegate.highlighted ? Theme.primary : "transparent"
            radius: 6
        }
    }

    indicator: Text {
        x: control.width - width - 12
        y: (control.height - height) / 2
        text: "󰅀"
        color: Theme.primary
        opacity: 0.6
        font.pixelSize: 12
    }

    contentItem: Text {
        leftPadding: 12
        rightPadding: control.indicator.width + 16
        text: control.displayText
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.primary
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06)
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
        border.width: 1
        radius: 11
    }

    popup: Popup {
        y: control.height + 4
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 280)
        padding: 4

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator { }
        }

        background: Rectangle {
            color: Theme.background
            border.color: Theme.primary
            border.width: 1
            radius: 10
            opacity: 0.98
        }
    }
}
