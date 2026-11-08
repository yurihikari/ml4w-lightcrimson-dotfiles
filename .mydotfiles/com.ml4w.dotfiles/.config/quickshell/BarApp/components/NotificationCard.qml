import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.CustomTheme
import qs.BarApp.services

// One notification, as a toast or in the notification center: image / app
// icon, app name and age, summary, body (with links), action buttons and an
// inline reply field when the app asks for one.
//
// Clicking it runs the app's default action (then it closes, like SwayNC);
// without one, a click expands a long body. The close button shows on hover.
Rectangle {
    id: card
    property var notif: null
    property bool toast: false          // toasts draw their own background
    property bool selected: false       // keyboard selection in the center
    property bool expanded: false
    readonly property bool hovered: hover.hovered
    readonly property bool critical: notif !== null && notif.urgency === NotificationUrgency.Critical
    // Emitted after a click or button ran one of the notification's actions.
    signal actionInvoked()

    readonly property string image: Notifs.imageSource(notif)
    readonly property string appIcon: Notifs.appIconSource(notif)
    readonly property var buttons: Notifs.buttonActions(notif)
    readonly property bool hasDefault: Notifs.defaultAction(notif) !== null

    implicitHeight: content.implicitHeight + 2 * pad
    readonly property int pad: 14

    radius: PanelStyle.radiusCard
    color: toast ? "transparent"
         : (selected || hovered ? PanelStyle.cardHover : PanelStyle.cardFill)
    Behavior on color { ColorAnimation { duration: 150 } }

    HoverHandler { id: hover }

    // Whole-card click (buttons, links and the reply field sit on top of it)
    MouseArea {
        anchors.fill: parent
        cursorShape: card.hasDefault ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (Notifs.activate(card.notif)) card.actionInvoked()
            else card.expanded = !card.expanded
        }
    }

    // Critical: a strip in the error color along the leading edge
    Rectangle {
        visible: card.critical
        anchors.left: parent.left; anchors.leftMargin: card.toast ? 2 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: 4; height: parent.height - 2 * card.pad
        radius: 2
        color: Theme.error
    }

    RowLayout {
        id: content
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: card.pad
        spacing: 12

        // ── Image / icon ────────────────────────────────────────────────────
        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 44; Layout.preferredHeight: 44

            ClippingRectangle {
                anchors.fill: parent
                radius: PanelStyle.radiusControl
                color: Theme.withAlpha(Theme.primary, 0.12)

                Image {
                    id: mainImage
                    anchors.fill: parent
                    anchors.margins: card.image !== "" ? 0 : 8
                    source: card.image !== "" ? card.image : card.appIcon
                    fillMode: card.image !== "" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                    sourceSize.width: 88; sourceSize.height: 88
                    asynchronous: true; smooth: true
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: mainImage.status !== Image.Ready
                    text: card.critical ? "󰀦" : "󰂚"
                    color: card.critical ? Theme.error : Theme.primary
                    font.pixelSize: 20
                }
            }

            // App badge on top of a picture (when both exist)
            Rectangle {
                visible: card.image !== "" && card.appIcon !== ""
                width: 20; height: 20; radius: 6
                anchors.right: parent.right; anchors.bottom: parent.bottom
                anchors.rightMargin: -4; anchors.bottomMargin: -4
                color: Theme.background
                Image {
                    anchors.fill: parent; anchors.margins: 2
                    source: card.appIcon
                    sourceSize.width: 32; sourceSize.height: 32
                    asynchronous: true
                }
            }
        }

        // ── Text, actions, reply ────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: card.notif ? (card.notif.appName || "Notification") : ""
                    color: Theme.primary; opacity: PanelStyle.dim
                    font.pixelSize: 11; font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    text: card.notif ? Notifs.timeAgo(card.notif, Notifs.now) : ""
                    color: Theme.primary; opacity: PanelStyle.faint
                    font.pixelSize: 11
                    visible: !closeBtn.visible
                }
                // Close
                Rectangle {
                    id: closeBtn
                    visible: card.hovered || card.selected
                    width: 20; height: 20; radius: 10
                    color: closeMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.18) : Theme.withAlpha(Theme.primary, 0.08)
                    Text { anchors.centerIn: parent; text: "󰅖"; color: Theme.primary; font.pixelSize: 12 }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent; anchors.margins: -4
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.dismiss(card.notif)
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notif ? card.notif.summary : ""
                color: card.critical ? Theme.error : Theme.primary
                font.pixelSize: 14; font.bold: true
                wrapMode: card.expanded ? Text.Wrap : Text.NoWrap
                elide: card.expanded ? Text.ElideNone : Text.ElideRight
                maximumLineCount: card.expanded ? 6 : 1
            }

            Text {
                id: bodyText
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notif ? card.notif.body : ""
                textFormat: Text.StyledText
                color: Theme.primary; opacity: 0.85
                linkColor: Theme.tertiary
                font.pixelSize: PanelStyle.bodySize
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: card.expanded ? 40 : (card.toast ? 3 : 2)
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // Action buttons
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: card.buttons.length > 0
                spacing: 6
                Repeater {
                    model: card.buttons
                    PanelButton {
                        required property var modelData
                        text: modelData.text
                        onClicked: { Notifs.invoke(card.notif, modelData); card.actionInvoked() }
                    }
                }
            }

            // Inline reply
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: card.notif !== null && card.notif.hasInlineReply
                spacing: 6
                PanelField {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    focused: replyField.activeFocus
                    TextField {
                        id: replyField
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        placeholderText: card.notif && card.notif.inlineReplyPlaceholder !== "" ? card.notif.inlineReplyPlaceholder : "Reply…"
                        placeholderTextColor: Theme.withAlpha(Theme.primary, PanelStyle.faint)
                        color: Theme.primary; font.pixelSize: 13
                        background: null
                        verticalAlignment: TextInput.AlignVCenter
                        onAccepted: sendBtn.clicked()
                    }
                }
                PanelButton {
                    id: sendBtn
                    Layout.preferredHeight: 34
                    icon: "󰒊"
                    accent: true
                    enabled: replyField.text.trim() !== ""
                    onClicked: {
                        card.notif.sendInlineReply(replyField.text.trim())
                        replyField.text = ""
                        card.actionInvoked()
                    }
                }
            }
        }
    }
}
