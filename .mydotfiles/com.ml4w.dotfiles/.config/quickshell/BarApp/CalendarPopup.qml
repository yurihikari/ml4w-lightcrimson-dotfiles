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
    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: WlrLayershell.None
    color: "transparent"

    MouseArea { anchors.fill: parent; onClicked: root.active = false }

    property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    property var dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    property int currentMonth: new Date().getMonth()
    property int currentYear: new Date().getFullYear()

    ListModel { id: calendarModel }

    function updateCalendar(year, month) {
        calendarModel.clear()
        let firstDay = new Date(year, month, 1)
        let startingDay = firstDay.getDay()
        let startCell = startingDay === 0 ? 6 : startingDay - 1
        let daysInMonth = new Date(year, month + 1, 0).getDate()
        let prevMonthDays = new Date(year, month, 0).getDate()
        let now = new Date()

        for (let row = 0; row < 6; row++) {
            // 1. Calculate Week Number for this row
            let dRow = new Date(year, month, 1 + (row * 7) - startCell)
            let target = new Date(dRow.valueOf())
            let dayNr = (dRow.getDay() + 6) % 7
            target.setDate(target.getDate() - dayNr + 3)
            let firstThursday = target.valueOf()
            target.setMonth(0, 1)
            if (target.getDay() !== 4) target.setMonth(0, 1 + ((4 - target.getDay()) + 7) % 7)
            let weekNo = 1 + Math.ceil((firstThursday - target) / 604800000)
            
            // Add Week Number to model
            calendarModel.append({ d: weekNo, cur: false, tod: false, type: "week" })

            // 2. Add 7 days for this row
            for (let col = 0; col < 7; col++) {
                let i = (row * 7) + col
                let dayNum, isCur, isTod
                if (i < startCell) {
                    dayNum = prevMonthDays - startCell + i + 1; isCur = false; isTod = false
                } else if (i < startCell + daysInMonth) {
                    dayNum = i - startCell + 1
                    isCur = true
                    isTod = (dayNum === now.getDate() && month === now.getMonth() && year === now.getFullYear())
                } else {
                    dayNum = i - startCell - daysInMonth + 1; isCur = false; isTod = false
                }
                calendarModel.append({ d: dayNum, cur: isCur, tod: isTod, type: "day" })
            }
        }
    }
    Component.onCompleted: updateCalendar(currentYear, currentMonth)

    Rectangle {
        width: 400; height: 520; anchors.top: parent.top; anchors.topMargin: 45
        anchors.right: parent.right; anchors.rightMargin: 155
        radius: 30; color: "transparent"; border.color: "transparent"; border.width: 1
        Rectangle {
            anchors.fill: parent
            color: Theme.background
            border.color: Theme.primary
            border.width: 2
            radius: 30
            opacity: 0.8 // Only the background is transparent
        }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 30; spacing: 20

            // Clock Header
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                Text {
                    id: bigTime; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDateTime(new Date(), "HH:mm:ss")
                    color: Theme.primary; font.pixelSize: 48; font.weight: Font.Black
                    Timer { interval: 1000; running: true; repeat: true; onTriggered: bigTime.text = Qt.formatDateTime(new Date(), "HH:mm:ss") }
                }
                Text {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDateTime(new Date(), "dddd, MMMM d")
                    color: Theme.primary; opacity: 0.6; font.pixelSize: 16
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

            // Month Nav
            RowLayout {
                Layout.fillWidth: true
                Text { text: ""; color: Theme.primary; font.pixelSize: 18; MouseArea { anchors.fill: parent; onClicked: { if (currentMonth === 0) { currentMonth = 11; currentYear-- } else currentMonth--; updateCalendar(currentYear, currentMonth) } } }
                Text { text: monthNames[currentMonth] + " " + currentYear; color: Theme.primary; font.bold: true; font.pixelSize: 18; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                Text { text: ""; color: Theme.primary; font.pixelSize: 18; MouseArea { anchors.fill: parent; onClicked: { if (currentMonth === 11) { currentMonth = 0; currentYear++ } else currentMonth++; updateCalendar(currentYear, currentMonth) } } }
            }

            // UNIFIED GRID (8 columns)
            GridLayout {
                columns: 8; rowSpacing: 12; columnSpacing: 10; Layout.fillWidth: true
                
                // Headers
                Text { text: "Wk"; color: Theme.primary; opacity: 0.3; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                Repeater {
                    model: dayNames
                    Text { text: modelData; color: Theme.primary; font.bold: true; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter; opacity: 0.5 }
                }

                // Data (Days and Weeks combined)
                Repeater {
                    model: calendarModel
                    Item {
                        Layout.preferredWidth: 32; Layout.preferredHeight: 32
                        Rectangle {
                            anchors.fill: parent; radius: 16
                            color: model.tod ? Theme.primary : "transparent"
                            visible: model.type === "day"
                            Text { 
                                anchors.centerIn: parent; text: model.d
                                color: model.tod ? Theme.background : Theme.primary
                                opacity: model.cur ? 1.0 : 0.25; font.bold: model.tod; font.pixelSize: 12
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: model.type === "week"
                            text: model.d; color: Theme.primary; opacity: 0.3; font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}