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
    WlrLayershell.keyboardFocus: WlrLayershell.OnDemand
    color: "transparent"

    MouseArea { anchors.fill: parent; onClicked: root.active = false }

    // ─── Calendar state ────────────────────────────────────────────────────
    property var monthNames: ["January","February","March","April","May","June","July","August","September","October","November","December"]
    property var dayNames: ["Mo","Tu","We","Th","Fr","Sa","Su"]
    property int currentMonth: new Date().getMonth()
    property int currentYear:  new Date().getFullYear()

    ListModel { id: calendarModel }

    function updateCalendar(year, month) {
        calendarModel.clear()
        let firstDay     = new Date(year, month, 1)
        let startingDay  = firstDay.getDay()
        let startCell    = startingDay === 0 ? 6 : startingDay - 1
        let daysInMonth  = new Date(year, month + 1, 0).getDate()
        let prevMonthDays= new Date(year, month, 0).getDate()
        let now          = new Date()

        for (let row = 0; row < 6; row++) {
            let dRow   = new Date(year, month, 1 + (row * 7) - startCell)
            let target = new Date(dRow.valueOf())
            let dayNr  = (dRow.getDay() + 6) % 7
            target.setDate(target.getDate() - dayNr + 3)
            let firstThursday = target.valueOf()
            target.setMonth(0, 1)
            if (target.getDay() !== 4) target.setMonth(0, 1 + ((4 - target.getDay()) + 7) % 7)
            let weekNo = 1 + Math.ceil((firstThursday - target) / 604800000)
            calendarModel.append({ d: weekNo, cur: false, tod: false, type: "week" })

            for (let col = 0; col < 7; col++) {
                let i = (row * 7) + col
                let dayNum, isCur, isTod
                if (i < startCell) {
                    dayNum = prevMonthDays - startCell + i + 1; isCur = false; isTod = false
                } else if (i < startCell + daysInMonth) {
                    dayNum = i - startCell + 1
                    isCur  = true
                    isTod  = (dayNum === now.getDate() && month === now.getMonth() && year === now.getFullYear())
                } else {
                    dayNum = i - startCell - daysInMonth + 1; isCur = false; isTod = false
                }
                calendarModel.append({ d: dayNum, cur: isCur, tod: isTod, type: "day" })
            }
        }
    }
    Component.onCompleted: updateCalendar(currentYear, currentMonth)

    // ─── Weather state ─────────────────────────────────────────────────────
    property string displayCity:  ""
    property string weatherDesc:  ""
    property real   tempC:        0
    property real   feelsLikeC:   0
    property int    humidity:     0
    property real   windKph:      0
    property int    weatherCode:  -1
    property bool   isDay:        true
    property bool   wxLoading:    false
    property string wxError:      ""
    property string cityInput:    ""

    property var forecastDates:   []
    property var forecastTempMax: []
    property var forecastTempMin: []
    property var forecastCodes:   []

    property real geoLat: 0
    property real geoLon: 0

    // ─── WMO helpers ──────────────────────────────────────────────────────
    function wmoIcon(code, day) {
        if (code === 0)  return day ? "󰖙" : "󰖔"
        if (code <= 2)   return day ? "󰖕" : "󰖕"
        if (code === 3)  return "󰖐"
        if (code <= 48)  return "󰖑"
        if (code <= 57)  return "󰖗"
        if (code <= 65)  return "󰖖"
        if (code <= 77)  return "󰖘"
        if (code <= 82)  return "󰖗"
        if (code <= 86)  return "󰼶"
        if (code <= 99)  return "󰙾"
        return "󰖙"
    }
    function wmoDesc(code) {
        if (code === 0)  return "Clear sky"
        if (code === 1)  return "Mainly clear"
        if (code === 2)  return "Partly cloudy"
        if (code === 3)  return "Overcast"
        if (code <= 48)  return "Foggy"
        if (code <= 55)  return "Drizzle"
        if (code <= 57)  return "Freezing drizzle"
        if (code <= 65)  return "Rain"
        if (code <= 67)  return "Freezing rain"
        if (code <= 77)  return "Snow"
        if (code <= 82)  return "Rain showers"
        if (code <= 86)  return "Snow showers"
        if (code <= 99)  return "Thunderstorm"
        return "Unknown"
    }
    function shortDay(dateStr) {
        let d = new Date(dateStr)
        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d.getDay()]
    }

    // ─── Processes ────────────────────────────────────────────────────────
    Process {
        id: ipGeoProc
        command: ["curl", "-sf", "--max-time", "5", "http://ip-api.com/json/?fields=city,lat,lon,status"]
        stdout: SplitParser {
            onRead: {
                try {
                    let j = JSON.parse(data.trim())
                    if (j.status === "success") {
                        root.displayCity = j.city
                        root.geoLat = j.lat; root.geoLon = j.lon
                        fetchWeather(j.lat, j.lon)
                    } else { root.wxError = "Location unavailable"; root.wxLoading = false }
                } catch(e) { root.wxError = "Network error"; root.wxLoading = false }
            }
        }
    }

    Process {
        id: geocodeProc
        stdout: SplitParser {
            onRead: {
                try {
                    let j = JSON.parse(data.trim())
                    if (j.results && j.results.length > 0) {
                        let r = j.results[0]
                        root.displayCity = r.name + (r.country_code ? ", " + r.country_code : "")
                        root.geoLat = r.latitude; root.geoLon = r.longitude
                        fetchWeather(r.latitude, r.longitude)
                    } else { root.wxError = "City not found"; root.wxLoading = false }
                } catch(e) { root.wxError = "Geocode error"; root.wxLoading = false }
            }
        }
    }

    Process {
        id: weatherProc
        stdout: SplitParser {
            onRead: {
                try {
                    let j = JSON.parse(data.trim())
                    let c = j.current
                    root.weatherCode  = c.weather_code
                    root.tempC        = c.temperature_2m
                    root.feelsLikeC   = c.apparent_temperature
                    root.humidity     = c.relative_humidity_2m
                    root.windKph      = c.wind_speed_10m
                    root.isDay        = c.is_day === 1
                    root.weatherDesc  = wmoDesc(c.weather_code)
                    root.forecastDates   = j.daily.time
                    root.forecastTempMax = j.daily.temperature_2m_max
                    root.forecastTempMin = j.daily.temperature_2m_min
                    root.forecastCodes   = j.daily.weather_code
                    root.wxLoading = false; root.wxError = ""
                } catch(e) { root.wxError = "Weather error"; root.wxLoading = false }
            }
        }
    }

    function fetchWeather(la, lo) {
        let url = "https://api.open-meteo.com/v1/forecast" +
                  "?latitude=" + la + "&longitude=" + lo +
                  "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day" +
                  "&daily=temperature_2m_max,temperature_2m_min,weather_code" +
                  "&wind_speed_unit=kmh&forecast_days=5&timezone=auto"
        weatherProc.command = ["curl", "-sf", "--max-time", "8", url]
        weatherProc.running = true
    }

    function loadCity(name) {
        root.wxLoading = true; root.wxError = ""
        if (!name || name.trim() === "") {
            ipGeoProc.running = true
        } else {
            let enc = encodeURIComponent(name.trim())
            geocodeProc.command = ["curl", "-sf", "--max-time", "6",
                "https://geocoding-api.open-meteo.com/v1/search?name=" + enc + "&count=1&language=en&format=json"]
            geocodeProc.running = true
        }
    }

    onActiveChanged: { if (active && weatherCode === -1) loadCity("") }

    // ─── Outer container — two panels side by side ─────────────────────────
    Row {
        anchors.top:        parent.top
        anchors.topMargin:  45
        anchors.right:      parent.right
        anchors.rightMargin: 155
        spacing: 10

        // ══════════════════════════════════════════════════════════════════
        //  LEFT — WEATHER PANEL
        // ══════════════════════════════════════════════════════════════════
        Rectangle {
            width: 260; height: 520
            radius: 30; color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: Theme.background
                border.color: Theme.primary; border.width: 2
                radius: 30; opacity: 0.8
            }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 0

                // ── Search bar ──────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true; height: 30; radius: 15
                    color: Theme.background; opacity: 1
                    border.color: Theme.primary; border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 8
                        spacing: 5

                        Text {
                            text: "󰍉"; color: Theme.primary; opacity: 0.4
                            font.pixelSize: 12; verticalAlignment: Text.AlignVCenter
                        }
                        Item {
                            Layout.fillWidth: true
                            height: 20
                            Text {
                                anchors.fill: parent
                                text: root.displayCity !== "" ? root.displayCity : "Search city…"
                                color: Theme.primary; opacity: 0.4; font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                visible: cityField.text.length === 0
                                elide: Text.ElideRight
                            }
                            TextInput {
                                id: cityField
                                anchors.fill: parent
                                color: Theme.primary; font.pixelSize: 12
                                verticalAlignment: TextInput.AlignVCenter
                                onAccepted: { root.cityInput = text; loadCity(text) }
                                Keys.onEscapePressed: root.active = false
                            }
                        }
                        Text {
                            text: "󰅖"; color: Theme.primary; opacity: 0.3; font.pixelSize: 11
                            visible: cityField.text.length > 0
                            verticalAlignment: Text.AlignVCenter
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { cityField.text = ""; root.cityInput = ""; loadCity("") }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 16 }

                // ── Loading / Error ─────────────────────────────────────
                Item {
                    Layout.fillWidth: true; height: 20
                    visible: root.wxLoading || root.wxError !== ""
                    Text {
                        anchors.centerIn: parent
                        text: root.wxLoading ? "Updating…" : root.wxError
                        color: root.wxError !== "" ? "#ff6b6b" : Theme.primary
                        opacity: 0.55; font.pixelSize: 11
                    }
                }

                // ── Big icon + temp ─────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    height: bigIcon.implicitHeight + 4
                    visible: root.weatherCode !== -1 && !root.wxLoading

                    Text {
                        id: bigIcon
                        anchors.left: parent.left; anchors.top: parent.top
                        text: wmoIcon(root.weatherCode, root.isDay)
                        color: Theme.primary; font.pixelSize: 52
                    }
                    Column {
                        anchors.right: parent.right
                        anchors.verticalCenter: bigIcon.verticalCenter
                        spacing: -2
                        Text {
                            text: Math.round(root.tempC) + "°"
                            color: Theme.primary; font.pixelSize: 44; font.weight: Font.Black
                            horizontalAlignment: Text.AlignRight; anchors.right: parent.right
                        }
                        Text {
                            text: root.weatherDesc
                            color: Theme.primary; opacity: 0.5; font.pixelSize: 11
                            horizontalAlignment: Text.AlignRight; anchors.right: parent.right
                        }
                    }
                }

                Item { Layout.preferredHeight: 10 }

                // ── City name ───────────────────────────────────────────
                Text {
                    Layout.fillWidth: true
                    text: root.displayCity
                    color: Theme.primary; opacity: 0.55; font.pixelSize: 12; font.weight: Font.Medium
                    elide: Text.ElideRight
                    visible: root.weatherCode !== -1
                }

                Item { Layout.preferredHeight: 14 }

                // ── Stat chips row ──────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    visible: root.weatherCode !== -1 && !root.wxLoading

                    Repeater {
                        model: [
                            { icon: "󰖌", val: Math.round(root.feelsLikeC) + "°C" },
                            { icon: "󰖎", val: root.humidity + "%" },
                            { icon: "󰖝", val: Math.round(root.windKph) + "" }
                        ]
                        Rectangle {
                            Layout.fillWidth: true; height: 40; radius: 12
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.07)
                            Column {
                                anchors.centerIn: parent; spacing: 1
                                Text { text: modelData.icon; color: Theme.primary; font.pixelSize: 14; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: modelData.val;  color: Theme.primary; font.pixelSize: 10; font.weight: Font.Bold; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 18 }

                // ── Divider ─────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Theme.primary; opacity: 0.1
                    visible: root.forecastDates.length > 0
                }

                Item { Layout.preferredHeight: 14 }

                // ── 5-day forecast ──────────────────────────────────────
                // OPTIMIZATION: pre-compute allMin/allMax once, outside the Repeater
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 10
                    visible: root.forecastDates.length > 0 && !root.wxLoading

                    // Compute range once for the whole forecast block
                    property real allMax: {
                        let m = -999
                        for (let i = 0; i < root.forecastTempMax.length; i++)
                            if (root.forecastTempMax[i] > m) m = root.forecastTempMax[i]
                        return m
                    }
                    property real allMin: {
                        let m = 999
                        for (let i = 0; i < root.forecastTempMin.length; i++)
                            if (root.forecastTempMin[i] < m) m = root.forecastTempMin[i]
                        return m
                    }
                    property real span: Math.max(1, allMax - allMin)

                    Repeater {
                        model: Math.min(5, root.forecastDates.length)
                        RowLayout {
                            Layout.fillWidth: true; spacing: 0

                            // Day label
                            Text {
                                text: index === 0 ? "Today" : shortDay(root.forecastDates[index])
                                color: Theme.primary
                                opacity: index === 0 ? 1.0 : 0.55
                                font.pixelSize: 11; font.weight: index === 0 ? Font.Bold : Font.Normal
                                Layout.preferredWidth: 38
                            }

                            // Icon
                            Text {
                                text: wmoIcon(root.forecastCodes[index] || 0, true)
                                color: Theme.primary; font.pixelSize: 13
                                Layout.preferredWidth: 20; horizontalAlignment: Text.AlignHCenter
                            }

                            Item { Layout.fillWidth: true }

                            // Min
                            Text {
                                text: Math.round(root.forecastTempMin[index] || 0) + "°"
                                color: Theme.primary; opacity: 0.4; font.pixelSize: 11
                                Layout.preferredWidth: 26; horizontalAlignment: Text.AlignRight
                            }

                            // Temp bar — references parent ColumnLayout's pre-computed span
                            Rectangle {
                                Layout.preferredWidth: 50; height: 3; radius: 2
                                Layout.leftMargin: 5; Layout.rightMargin: 5
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                property real barLeft:  (root.forecastTempMin[index] - parent.parent.allMin) / parent.parent.span
                                property real barRight: (root.forecastTempMax[index] - parent.parent.allMin) / parent.parent.span
                                Rectangle {
                                    x: parent.barLeft * parent.width
                                    width: (parent.barRight - parent.barLeft) * parent.width
                                    height: parent.height; radius: 2
                                    color: Theme.primary; opacity: 0.75
                                }
                            }

                            // Max
                            Text {
                                text: Math.round(root.forecastTempMax[index] || 0) + "°"
                                color: Theme.primary; font.pixelSize: 11; font.weight: Font.Bold
                                Layout.preferredWidth: 26
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true; Layout.fillHeight: true }

                // ── Refresh hint ────────────────────────────────────────
                Text {
                    Layout.alignment: Qt.AlignRight
                    text: "󰑓"
                    color: Theme.primary; opacity: 0.2; font.pixelSize: 13
                    MouseArea {
                        anchors.fill: parent
                        onClicked: loadCity(root.cityInput)
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════
        //  RIGHT — CALENDAR PANEL 
        // ══════════════════════════════════════════════════════════════════
        Rectangle {
            width: 400; height: 520
            radius: 30; color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: Theme.background
                border.color: Theme.primary; border.width: 2
                radius: 30; opacity: 0.8
            }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 30; spacing: 20

                // Clock header — OPTIMIZATION: single Timer + one Date property
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    property var now: new Date()
                    Timer { interval: 1000; running: true; repeat: true; onTriggered: parent.now = new Date() }
                    Text {
                        id: bigTime
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDateTime(parent.now, "HH:mm:ss")
                        color: Theme.primary; font.pixelSize: 48; font.weight: Font.Black
                    }
                    Text {
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDateTime(parent.now, "dddd, MMMM d")
                        color: Theme.primary; opacity: 0.6; font.pixelSize: 16
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }

                // Month nav
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: ""; color: Theme.primary; font.pixelSize: 18
                        MouseArea { anchors.fill: parent; onClicked: { if (currentMonth === 0) { currentMonth = 11; currentYear-- } else currentMonth--; updateCalendar(currentYear, currentMonth) } }
                    }
                    Text {
                        text: monthNames[currentMonth] + " " + currentYear
                        color: Theme.primary; font.bold: true; font.pixelSize: 18
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        text: ""; color: Theme.primary; font.pixelSize: 18
                        MouseArea { anchors.fill: parent; onClicked: { if (currentMonth === 11) { currentMonth = 0; currentYear++ } else currentMonth++; updateCalendar(currentYear, currentMonth) } }
                    }
                }

                // Unified 8-column grid
                GridLayout {
                    columns: 8; rowSpacing: 12; columnSpacing: 10; Layout.fillWidth: true

                    Text { text: "Wk"; color: Theme.primary; opacity: 0.3; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                    Repeater {
                        model: dayNames
                        Text { text: modelData; color: Theme.primary; font.bold: true; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter; opacity: 0.5 }
                    }

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
                                    opacity: model.cur ? 1.0 : 0.25
                                    font.bold: model.tod; font.pixelSize: 12
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
}
