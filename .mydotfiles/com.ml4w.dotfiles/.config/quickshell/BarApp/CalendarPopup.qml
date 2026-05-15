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
    
    // KEEP VISIBLE DURING OUTRO ANIMATION
    visible: active || mainContent.opacity > 0
    
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: WlrLayershell.Ignore
    WlrLayershell.keyboardFocus: WlrLayershell.OnDemand
    color: "transparent"

    MouseArea { 
        anchors.fill: parent
        onClicked: root.active = false 
    }

    // ─── Global Time State (Robust & Always Accessible) ─────────────────────
    property var localNow: new Date()
    property var worldNow: new Date()
    
    Timer { 
        interval: 1000
        running: true
        repeat: true 
        onTriggered: {
            root.localNow = new Date()
            if (root.showWorldClock && root.targetWcCity !== "") {
                let utcMs = root.localNow.getTime()
                let offsetDiffMs = (root.targetWcOffsetSeconds * 1000) + (root.localNow.getTimezoneOffset() * 60000)
                root.worldNow = new Date(utcMs + offsetDiffMs)
            }
        }
    }

    // ─── Calendar state ────────────────────────────────────────────────────
    property var monthNames: ["January","February","March","April","May","June","July","August","September","October","November","December"]
    property var dayNames: ["Mo","Tu","We","Th","Fr","Sa","Su"]
    property int currentMonth: new Date().getMonth()
    property int currentYear:  new Date().getFullYear()

    ListModel { id: calendarModel }
    ListModel { id: hourlyModel }

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
                    dayNum = prevMonthDays - startCell + i + 1
                    isCur = false
                    isTod = false
                } else if (i < startCell + daysInMonth) {
                    dayNum = i - startCell + 1
                    isCur  = true
                    isTod  = (dayNum === now.getDate() && month === now.getMonth() && year === now.getFullYear())
                } else {
                    dayNum = i - startCell - daysInMonth + 1
                    isCur = false
                    isTod = false
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
    property real   uvIndex:      0
    property real   precipMm:     0
    property int    weatherCode:  -1
    property bool   isDay:        true
    property bool   wxLoading:    false
    property string wxError:      ""
    property string cityInput:    ""
    property int    weatherTab:   0 // 0 = Today (Hourly), 1 = 5-Day

    property var forecastDates:   []
    property var forecastTempMax: []
    property var forecastTempMin: []
    property var forecastCodes:   []
    property var forecastPrecip:  []

    property real geoLat: 0
    property real geoLon: 0

    // ─── World Clock state ─────────────────────────────────────────────────
    property bool   showWorldClock: false
    property string targetWcCity: ""
    property string targetWcTz: ""
    property int    targetWcOffsetSeconds: 0
    property bool   wcLoading: false
    property string wcError: ""

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
    function getWcTimeDiffString() {
        let localOffsetSec = -(new Date().getTimezoneOffset() * 60)
        let diffSec = root.targetWcOffsetSeconds - localOffsetSec
        if (diffSec === 0) return "Same time zone"
        let hrs = Math.abs(diffSec / 3600)
        let suffix = diffSec > 0 ? " ahead" : " behind"
        let hrStr = hrs % 1 === 0 ? hrs.toString() : hrs.toFixed(1)
        return hrStr + (hrStr === "1" ? " hour" : " hours") + suffix
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
                        root.geoLat = j.lat
                        root.geoLon = j.lon
                        fetchWeather(j.lat, j.lon)
                    } else { 
                        root.wxError = "Location unavailable"
                        root.wxLoading = false 
                    }
                } catch(e) { 
                    root.wxError = "Network error"
                    root.wxLoading = false 
                }
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
                        root.geoLat = r.latitude
                        root.geoLon = r.longitude
                        fetchWeather(r.latitude, r.longitude)
                    } else { 
                        root.wxError = "City not found"
                        root.wxLoading = false 
                    }
                } catch(e) { 
                    root.wxError = "Geocode error"
                    root.wxLoading = false 
                }
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
                    root.uvIndex      = c.uv_index || 0
                    root.precipMm     = c.precipitation || 0
                    root.isDay        = c.is_day === 1
                    root.weatherDesc  = wmoDesc(c.weather_code)
                    
                    root.forecastDates   = j.daily.time
                    root.forecastTempMax = j.daily.temperature_2m_max
                    root.forecastTempMin = j.daily.temperature_2m_min
                    root.forecastCodes   = j.daily.weather_code
                    root.forecastPrecip  = j.daily.precipitation_probability_max || []

                    hourlyModel.clear()
                    let currentTargetMs = new Date(c.time).getTime()
                    let added = 0
                    for (let i = 0; i < j.hourly.time.length; i++) {
                        let t = new Date(j.hourly.time[i]).getTime()
                        if (t >= currentTargetMs - 3600000) {
                            let dateObj = new Date(t)
                            let hrStr = Qt.formatDateTime(dateObj, "HH:mm")
                            hourlyModel.append({
                                timeStr: (added === 0) ? "Now" : hrStr,
                                temp: Math.round(j.hourly.temperature_2m[i]),
                                code: j.hourly.weather_code[i],
                                precip: j.hourly.precipitation_probability[i],
                                isDay: j.hourly.is_day[i] === 1
                            })
                            added++
                            if (added >= 24) break;
                        }
                    }
                    
                    root.wxLoading = false
                    root.wxError = ""
                } catch(e) { 
                    root.wxError = "Weather error"
                    root.wxLoading = false 
                }
            }
        }
    }

    Process {
        id: wcGeocodeProc
        stdout: SplitParser {
            onRead: {
                try {
                    let j = JSON.parse(data.trim())
                    if (j.results && j.results.length > 0) {
                        let r = j.results[0]
                        root.targetWcCity = r.name + (r.country_code ? ", " + r.country_code : "")
                        root.targetWcTz = r.timezone || "UTC"
                        wcOffsetProc.command = ["sh", "-c", "TZ='" + root.targetWcTz + "' date +%z"]
                        wcOffsetProc.running = true
                    } else { 
                        root.wcError = "City not found"
                        root.wcLoading = false 
                    }
                } catch(e) { 
                    root.wcError = "Search error"
                    root.wcLoading = false 
                }
            }
        }
    }

    Process {
        id: wcOffsetProc
        stdout: SplitParser {
            onRead: {
                let str = data.trim()
                let sign = (str.charAt(0) === '-') ? -1 : 1
                let hours = parseInt(str.substring(1, 3))
                let mins = parseInt(str.substring(3, 5))
                root.targetWcOffsetSeconds = sign * ((hours * 3600) + (mins * 60))
                root.wcLoading = false
            }
        }
    }

    function fetchWeather(la, lo) {
        let url = "https://api.open-meteo.com/v1/forecast" +
                  "?latitude=" + la + "&longitude=" + lo +
                  "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day,precipitation,uv_index" +
                  "&hourly=temperature_2m,weather_code,precipitation_probability,is_day" +
                  "&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max" +
                  "&wind_speed_unit=kmh&forecast_days=5&timezone=auto"
        weatherProc.command = ["curl", "-sf", "--max-time", "8", url]
        weatherProc.running = true
    }

    function loadCity(name) {
        root.wxLoading = true
        root.wxError = ""
        if (!name || name.trim() === "") {
            ipGeoProc.running = true
        } else {
            let enc = encodeURIComponent(name.trim())
            geocodeProc.command = ["curl", "-sf", "--max-time", "6",
                "https://geocoding-api.open-meteo.com/v1/search?name=" + enc + "&count=1&language=en&format=json"]
            geocodeProc.running = true
        }
    }

    function loadWcCity(name) {
        if (!name || name.trim() === "") return
        root.wcLoading = true
        root.wcError = ""
        let enc = encodeURIComponent(name.trim())
        wcGeocodeProc.command = ["curl", "-sf", "--max-time", "6",
            "https://geocoding-api.open-meteo.com/v1/search?name=" + enc + "&count=1&language=en&format=json"]
        wcGeocodeProc.running = true
    }

    onActiveChanged: { 
        if (active && weatherCode === -1) {
            loadCity("") 
        }
    }

    // ─── UNIFIED MAIN CONTAINER ───────────────────────────────────────────
    Rectangle {
        id: mainContent
        anchors.top:        parent.top
        anchors.topMargin:  45
        anchors.right:      parent.right
        anchors.rightMargin: 155
        
        width: 900
        height: 580
        radius: 30
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.8)
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
        border.width: 2
        clip: true 

        opacity: root.active ? 1 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.OutExpo }
        }
        transform: Translate {
            y: root.active ? 0 : -20
            Behavior on y {
                NumberAnimation { duration: 250; easing.type: Easing.OutExpo }
            }
        }

        // ── LIGHTWEIGHT WEATHER BACKGROUND ANIMATIONS ────────────────────────
        Item {
            id: bgAnimItem
            anchors.fill: parent
            
            // WMO Logic Parsing
            property bool isClear:   weatherCode === 0 || weatherCode === 1
            property bool isCloudy:  weatherCode === 2 || weatherCode === 3
            property bool isFog:     weatherCode === 45 || weatherCode === 48
            property bool isThunder: weatherCode >= 95 && weatherCode <= 99
            property bool isRain:    (weatherCode >= 51 && weatherCode <= 67) || (weatherCode >= 80 && weatherCode <= 82) || isThunder
            property bool isSnow:    (weatherCode >= 71 && weatherCode <= 77) || (weatherCode >= 85 && weatherCode <= 86)

            // 1. SUN (Clear or Cloudy, Day)
            Text {
                text: "󰖙"
                color: Theme.primary
                font.pixelSize: 380
                anchors.centerIn: parent
                visible: (bgAnimItem.isClear || bgAnimItem.isCloudy) && root.isDay && !root.wxLoading
                opacity: 0.04
                RotationAnimation on rotation { 
                    loops: Animation.Infinite 
                    from: 0 
                    to: 360 
                    duration: 90000 
                    running: parent.visible 
                }
            }

            // 2. MOON (Clear or Cloudy, Night)
            Text {
                text: "󰖔" // MDI Moon
                color: Theme.primary
                font.pixelSize: 320
                anchors.centerIn: parent
                visible: (bgAnimItem.isClear || bgAnimItem.isCloudy) && !root.isDay && !root.wxLoading
                opacity: 0.04
                
                SequentialAnimation on rotation {
                    loops: Animation.Infinite
                    running: parent.visible
                    NumberAnimation { from: -5; to: 5; duration: 8000; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 5; to: -5; duration: 8000; easing.type: Easing.InOutSine }
                }
            }

            // 3. STARS (Clear, Night)
            Repeater {
                model: bgAnimItem.isClear && !root.isDay && !root.wxLoading ? 20 : 0
                Text {
                    property real startX: Math.random() * mainContent.width
                    property real startY: Math.random() * (mainContent.height * 0.7)
                    property real animDelay: Math.random() * 3000
                    
                    x: startX
                    y: startY
                    text: "✦"
                    color: Theme.primary
                    font.pixelSize: 10 + Math.random() * 14
                    opacity: 0.0
                    
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: root.active
                        PauseAnimation { duration: animDelay }
                        NumberAnimation { to: 0.15; duration: 1500; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.0; duration: 1500; easing.type: Easing.InOutSine }
                        PauseAnimation { duration: 2000 + Math.random() * 3000 }
                    }
                }
            }

            // 4. CLOUDS (Cloudy Day/Night)
            Repeater {
                model: bgAnimItem.isCloudy && !root.wxLoading ? 3 : 0
                Text {
                    property real startY: 20 + Math.random() * (mainContent.height * 0.4)
                    property real dur: 40000 + Math.random() * 40000
                    
                    y: startY
                    text: "󰖐"
                    color: Theme.primary
                    font.pixelSize: 180 + Math.random() * 100
                    opacity: 0.03
                    
                    NumberAnimation on x {
                        from: -300
                        to: mainContent.width + 100
                        duration: dur
                        loops: Animation.Infinite
                        running: root.active
                    }
                }
            }

            // 5. FOG (Dense, low opacity drifting clouds)
            Repeater {
                model: bgAnimItem.isFog && !root.wxLoading ? 6 : 0
                Text {
                    property real startY: -50 + Math.random() * (mainContent.height - 100)
                    property real dur: 30000 + Math.random() * 40000
                    
                    y: startY
                    text: "󰖐"
                    color: Theme.primary
                    font.pixelSize: 300 + Math.random() * 200
                    opacity: 0.02
                    
                    NumberAnimation on x {
                        from: -400
                        to: mainContent.width + 200
                        duration: dur
                        loops: Animation.Infinite
                        running: root.active
                    }
                }
            }

            // 6. RAIN / SNOW Particles
            Repeater {
                model: (bgAnimItem.isRain || bgAnimItem.isSnow) && !root.wxLoading ? (bgAnimItem.isThunder ? 40 : 25) : 0
                Item {
                    property real startX: Math.random() * mainContent.width
                    property real startY: -50 - Math.random() * mainContent.height
                    property real dur: bgAnimItem.isSnow ? (3000 + Math.random() * 4000) : (600 + Math.random() * 400)
                    
                    x: startX
                    
                    Text { 
                        text: bgAnimItem.isSnow ? "󰜗" : "󰖖"
                        color: Theme.primary
                        font.pixelSize: bgAnimItem.isSnow ? (8 + Math.random() * 12) : 14
                        opacity: 0.15 + Math.random() * 0.1 
                    }
                    
                    NumberAnimation on y { 
                        from: startY
                        to: mainContent.height + 50
                        duration: dur
                        loops: Animation.Infinite
                        running: root.active 
                    }
                }
            }

            // 7. THUNDERSTORM (Lightning flashes)
            Rectangle {
                anchors.fill: parent
                color: Theme.primary
                opacity: 0.0
                visible: bgAnimItem.isThunder && !root.wxLoading

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: parent.visible
                    
                    PauseAnimation { duration: 3000 + Math.random() * 7000 }
                    
                    // First Flash
                    NumberAnimation { to: 0.15; duration: 50 }
                    NumberAnimation { to: 0.0; duration: 100 }
                    
                    PauseAnimation { duration: 50 + Math.random() * 100 }
                    
                    // Second Flash
                    NumberAnimation { to: 0.2; duration: 50 }
                    NumberAnimation { to: 0.0; duration: 400 }
                }
            }
        }
        // ──────────────────────────────────────────────────────────────────

        MouseArea { anchors.fill: parent } 

        RowLayout {
            anchors.fill: parent
            anchors.margins: 25
            spacing: 25

            // ══════════════════════════════════════════════════════════════════
            //  LEFT — WEATHER PANEL (With Tab System)
            // ══════════════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillHeight: true
                Layout.preferredWidth: 310
                spacing: 0

                // Search Bar
                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 16
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 6

                        Text { 
                            text: "󰍉"
                            color: Theme.primary
                            opacity: 0.5
                            font.pixelSize: 13
                            verticalAlignment: Text.AlignVCenter 
                        }

                        Item {
                            Layout.fillWidth: true
                            height: 20

                            Text { 
                                anchors.fill: parent
                                text: root.displayCity !== "" ? root.displayCity : "Search city…"
                                color: Theme.primary
                                opacity: 0.5
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                visible: cityField.text.length === 0
                                elide: Text.ElideRight 
                            }

                            TextInput { 
                                id: cityField
                                anchors.fill: parent
                                color: Theme.primary
                                font.pixelSize: 12
                                verticalAlignment: TextInput.AlignVCenter
                                onAccepted: { 
                                    root.cityInput = text
                                    loadCity(text) 
                                }
                                Keys.onEscapePressed: root.active = false 
                            }
                        }

                        Text { 
                            text: "󰅖"
                            color: Theme.primary
                            opacity: 0.4
                            font.pixelSize: 13
                            visible: cityField.text.length > 0
                            verticalAlignment: Text.AlignVCenter

                            MouseArea { 
                                anchors.fill: parent
                                onClicked: { 
                                    cityField.text = ""
                                    root.cityInput = ""
                                    loadCity("") 
                                } 
                            } 
                        }
                    }
                }

                Item { Layout.preferredHeight: 15 }

                // Error / Loading
                Item {
                    Layout.fillWidth: true
                    height: 15
                    visible: root.wxLoading || root.wxError !== ""

                    Text { 
                        anchors.centerIn: parent
                        text: root.wxLoading ? "Updating forecast…" : root.wxError
                        color: root.wxError !== "" ? "#ff6b6b" : Theme.primary
                        opacity: 0.6
                        font.pixelSize: 11 
                    }
                }

                // Current Big Stats
                Item {
                    Layout.fillWidth: true
                    height: bigIcon.implicitHeight + 4
                    visible: root.weatherCode !== -1 && !root.wxLoading

                    Text { 
                        id: bigIcon
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: wmoIcon(root.weatherCode, root.isDay)
                        color: Theme.primary
                        font.pixelSize: 58 
                    }

                    Column {
                        anchors.right: parent.right
                        anchors.verticalCenter: bigIcon.verticalCenter
                        spacing: -4

                        Text { 
                            text: Math.round(root.tempC) + "°"
                            color: Theme.primary
                            font.pixelSize: 48
                            font.weight: Font.Black
                            horizontalAlignment: Text.AlignRight
                            anchors.right: parent.right 
                        }
                        
                        Text { 
                            text: root.weatherDesc
                            color: Theme.primary
                            opacity: 0.6
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignRight
                            anchors.right: parent.right 
                        }
                    }
                }

                Item { Layout.preferredHeight: 10 }

                Text { 
                    Layout.fillWidth: true
                    text: root.displayCity
                    color: Theme.primary
                    opacity: 0.55
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    visible: root.weatherCode !== -1 
                }

                Item { Layout.preferredHeight: 16 }

                // ── TAB SWITCHER ──
                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    radius: 16
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                    visible: root.weatherCode !== -1 && !root.wxLoading

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            color: root.weatherTab === 0 ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent"
                            
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text { 
                                text: "Today"
                                color: Theme.primary
                                opacity: root.weatherTab === 0 ? 1.0 : 0.5
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                anchors.centerIn: parent 
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.weatherTab = 0 }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            color: root.weatherTab === 1 ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent"
                            
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text { 
                                text: "5-Day Forecast"
                                color: Theme.primary
                                opacity: root.weatherTab === 1 ? 1.0 : 0.5
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                anchors.centerIn: parent 
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.weatherTab = 1 }
                        }
                    }
                }

                Item { Layout.preferredHeight: 16 }

                // ── DYNAMIC CONTENT AREA ──
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // VIEW 1: TODAY (Chips + Hourly)
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        opacity: root.weatherTab === 0 ? 1.0 : 0.0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        // Stat Chips
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 8
                            rowSpacing: 8

                            Repeater {
                                model: [
                                    { icon: "󰖌", label: "Feels", val: Math.round(root.feelsLikeC) + "°C" },
                                    { icon: "󰖎", label: "Humid", val: root.humidity + "%" },
                                    { icon: "󰖝", label: "Wind",  val: Math.round(root.windKph) + " km/h" },
                                    { icon: "󰖑", label: "UV",    val: root.uvIndex + " Index" }
                                ]
                                
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 38
                                    radius: 10
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06)
                                    
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        
                                        Text { 
                                            text: modelData.icon
                                            color: Theme.primary
                                            font.pixelSize: 14
                                            opacity: 0.8 
                                        }
                                        
                                        Column { 
                                            Layout.fillWidth: true
                                            
                                            Text { 
                                                text: modelData.label
                                                color: Theme.primary
                                                font.pixelSize: 9
                                                opacity: 0.5 
                                            }
                                            
                                            Text { 
                                                text: modelData.val
                                                color: Theme.primary
                                                font.pixelSize: 10
                                                font.weight: Font.Bold 
                                            } 
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.preferredHeight: 16 }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.primary; opacity: 0.1 }
                        Item { Layout.preferredHeight: 16 }

                        // 24-HOUR SCROLLABLE FORECAST
                        ListView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 85 // Taller to prevent cropping
                            orientation: ListView.Horizontal
                            spacing: 16
                            clip: true
                            model: hourlyModel
                            interactive: true
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: ColumnLayout {
                                width: 48
                                spacing: 2 // Tighter spacing to fit nicely

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: model.timeStr
                                    color: Theme.primary
                                    opacity: model.timeStr === "Now" ? 1.0 : 0.6
                                    font.pixelSize: 11
                                    font.weight: model.timeStr === "Now" ? Font.Bold : Font.Normal
                                }
                                
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.wmoIcon(model.code, model.isDay)
                                    color: Theme.primary
                                    font.pixelSize: 18
                                }
                                
                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredHeight: 14
                                    Layout.preferredWidth: 40
                                    opacity: model.precip > 0 ? 1.0 : 0.0 
                                    
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        
                                        Text { 
                                            text: "󰖖"
                                            color: "#60a5fa"
                                            font.pixelSize: 9
                                            anchors.verticalCenter: parent.verticalCenter 
                                        }
                                        
                                        Text { 
                                            text: model.precip + "%"
                                            color: "#60a5fa"
                                            opacity: 0.9
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            anchors.verticalCenter: parent.verticalCenter 
                                        }
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: model.temp + "°"
                                    color: Theme.primary
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // VIEW 2: 5-DAY FORECAST
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 16
                        opacity: root.weatherTab === 1 ? 1.0 : 0.0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        property real allMax: { 
                            let m = -999; 
                            for(let i = 0; i < root.forecastTempMax.length; i++) {
                                if(root.forecastTempMax[i] > m) m = root.forecastTempMax[i];
                            }
                            return m;
                        }

                        property real allMin: { 
                            let m = 999; 
                            for(let i = 0; i < root.forecastTempMin.length; i++) {
                                if(root.forecastTempMin[i] < m) m = root.forecastTempMin[i];
                            }
                            return m;
                        }

                        property real span: Math.max(1, allMax - allMin)

                        Repeater {
                            model: Math.min(5, root.forecastDates.length)
                            
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                
                                Text { 
                                    text: index === 0 ? "Today" : shortDay(root.forecastDates[index])
                                    color: Theme.primary
                                    opacity: index === 0 ? 1.0 : 0.6
                                    font.pixelSize: 11
                                    font.weight: index === 0 ? Font.Bold : Font.Normal
                                    Layout.preferredWidth: 45 
                                }
                                
                                Text { 
                                    text: wmoIcon(root.forecastCodes[index] || 0, true)
                                    color: Theme.primary
                                    font.pixelSize: 14
                                    Layout.preferredWidth: 26
                                    horizontalAlignment: Text.AlignHCenter 
                                }
                                
                                Item {
                                    Layout.preferredWidth: 36
                                    Layout.fillHeight: true
                                    
                                    Row { 
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: root.forecastPrecip[index] > 0
                                        spacing: 2
                                        
                                        Text { 
                                            text: "󰖖"
                                            color: "#60a5fa"
                                            font.pixelSize: 9
                                            anchors.verticalCenter: parent.verticalCenter 
                                        }
                                        
                                        Text { 
                                            text: root.forecastPrecip[index] + "%"
                                            color: Theme.primary
                                            opacity: 0.5
                                            font.pixelSize: 9
                                            anchors.verticalCenter: parent.verticalCenter 
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }
                                
                                Text { 
                                    text: Math.round(root.forecastTempMin[index] || 0) + "°"
                                    color: Theme.primary
                                    opacity: 0.5
                                    font.pixelSize: 11
                                    Layout.preferredWidth: 26
                                    horizontalAlignment: Text.AlignRight 
                                }

                                Rectangle {
                                    Layout.preferredWidth: 70
                                    height: 4
                                    radius: 2
                                    Layout.leftMargin: 8
                                    Layout.rightMargin: 8
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                    property real barLeft:  (root.forecastTempMin[index] - parent.parent.allMin) / parent.parent.span
                                    property real barRight: (root.forecastTempMax[index] - parent.parent.allMin) / parent.parent.span
                                    
                                    Rectangle { 
                                        x: parent.barLeft * parent.width
                                        width: (parent.barRight - parent.barLeft) * parent.width
                                        height: parent.height
                                        radius: 2
                                        color: Theme.primary
                                        opacity: 0.8 
                                    }
                                }
                                
                                Text { 
                                    text: Math.round(root.forecastTempMax[index] || 0) + "°"
                                    color: Theme.primary
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    Layout.preferredWidth: 26 
                                }
                            }
                        }
                        
                        Item { Layout.fillHeight: true }
                    }
                }

                // Global refresh button
                Text { 
                    Layout.alignment: Qt.AlignRight
                    text: "󰑓"
                    color: Theme.primary
                    opacity: 0.3
                    font.pixelSize: 14
                    
                    MouseArea { 
                        anchors.fill: parent
                        anchors.margins: -10
                        onClicked: loadCity(root.cityInput) 
                    } 
                }
            }

            // ══════════════════════════════════════════════════════════════════
            //  CENTER DIVIDER
            // ══════════════════════════════════════════════════════════════════
            Rectangle {
                Layout.fillHeight: true
                width: 1
                color: Theme.primary
                opacity: 0.1
                Layout.topMargin: 10
                Layout.bottomMargin: 10
            }

            // ══════════════════════════════════════════════════════════════════
            //  RIGHT — CALENDAR / WORLD CLOCK PANEL 
            // ══════════════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillHeight: true
                Layout.fillWidth: true
                spacing: 15

                // ── Clock Header (Shared) ──────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    
                    Item { Layout.preferredWidth: 24 }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: -2
                        
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Qt.formatDateTime(root.localNow, "HH:mm:ss")
                            color: Theme.primary
                            font.pixelSize: 56
                            font.weight: Font.Black
                        }
                        
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Qt.formatDateTime(root.localNow, "dddd, MMMM d")
                            color: Theme.primary
                            opacity: 0.6
                            font.pixelSize: 16
                            font.weight: Font.Medium
                        }
                    }

                    // World Clock Toggle Button
                    Item {
                        Layout.preferredWidth: 24
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 10
                        
                        Text {
                            anchors.centerIn: parent
                            text: root.showWorldClock ? "󰃰" : "󰅐" 
                            color: Theme.primary
                            opacity: toggleWcMouse.containsMouse ? 0.9 : 0.4
                            font.pixelSize: 20
                            
                            Behavior on opacity { 
                                NumberAnimation { duration: 150 } 
                            }
                            
                            MouseArea {
                                id: toggleWcMouse
                                anchors.fill: parent
                                anchors.margins: -15
                                hoverEnabled: true
                                onClicked: root.showWorldClock = !root.showWorldClock
                            }
                        }
                    }
                }

                Item { 
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    
                    // ── Calendar View ──────────────────────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 20
                        opacity: root.showWorldClock ? 0.0 : 1.0
                        visible: opacity > 0
                        
                        Behavior on opacity { 
                            NumberAnimation { duration: 250; easing.type: Easing.OutExpo } 
                        }
                        
                        // Full Navigation Row
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            Layout.rightMargin: 10
                            
                            Text { 
                                text: "󰄾"
                                color: Theme.primary
                                font.pixelSize: 18
                                opacity: ypa.pressed ? 0.4 : 0.7
                                MouseArea { 
                                    id: ypa
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    onClicked: { 
                                        currentYear--; 
                                        updateCalendar(currentYear, currentMonth) 
                                    } 
                                } 
                            }
                            
                            Text { 
                                text: "󰅁"
                                color: Theme.primary
                                font.pixelSize: 22
                                opacity: mpa.pressed ? 0.4 : 0.9
                                Layout.leftMargin: 5
                                MouseArea { 
                                    id: mpa
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    onClicked: { 
                                        if (currentMonth === 0) { 
                                            currentMonth = 11; 
                                            currentYear-- 
                                        } else {
                                            currentMonth--
                                        } 
                                        updateCalendar(currentYear, currentMonth) 
                                    } 
                                } 
                            }
                            
                            Text {
                                text: monthNames[currentMonth] + " " + currentYear
                                color: Theme.primary
                                font.bold: true
                                font.pixelSize: 18
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onWheel: function(wheel) {
                                        if (wheel.angleDelta.y > 0) { 
                                            if (currentMonth === 11) { 
                                                currentMonth = 0; 
                                                currentYear++ 
                                            } else {
                                                currentMonth++ 
                                            }
                                        } else { 
                                            if (currentMonth === 0) { 
                                                currentMonth = 11; 
                                                currentYear-- 
                                            } else {
                                                currentMonth-- 
                                            }
                                        }
                                        updateCalendar(currentYear, currentMonth)
                                    }
                                }
                            }
                            
                            Text { 
                                text: "󰅂"
                                color: Theme.primary
                                font.pixelSize: 22
                                opacity: mna.pressed ? 0.4 : 0.9
                                Layout.rightMargin: 5
                                MouseArea { 
                                    id: mna
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    onClicked: { 
                                        if (currentMonth === 11) { 
                                            currentMonth = 0; 
                                            currentYear++ 
                                        } else {
                                            currentMonth++
                                        } 
                                        updateCalendar(currentYear, currentMonth) 
                                    } 
                                } 
                            }
                            
                            Text { 
                                text: "󰄿"
                                color: Theme.primary
                                font.pixelSize: 18
                                opacity: yna.pressed ? 0.4 : 0.7
                                MouseArea { 
                                    id: yna
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    onClicked: { 
                                        currentYear++; 
                                        updateCalendar(currentYear, currentMonth) 
                                    } 
                                } 
                            }
                        }

                        // Calendar grid
                        GridLayout {
                            columns: 8
                            rowSpacing: 14
                            columnSpacing: 12
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            
                            Text { 
                                text: "Wk"
                                color: Theme.primary
                                opacity: 0.3
                                font.pixelSize: 11
                                Layout.alignment: Qt.AlignHCenter 
                            }
                            
                            Repeater { 
                                model: dayNames
                                Text { 
                                    text: modelData
                                    color: Theme.primary
                                    font.bold: true
                                    font.pixelSize: 12
                                    Layout.alignment: Qt.AlignHCenter
                                    opacity: 0.5 
                                } 
                            }
                            
                            Repeater {
                                model: calendarModel
                                Item {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 18
                                        color: model.tod ? Theme.primary : "transparent"
                                        border.color: model.tod ? "transparent" : (model.cur ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1) : "transparent")
                                        border.width: 1
                                        visible: model.type === "day"
                                        
                                        Text { 
                                            anchors.centerIn: parent
                                            text: model.d
                                            color: model.tod ? Theme.background : Theme.primary
                                            opacity: model.tod ? 1.0 : (model.cur ? 0.9 : 0.25)
                                            font.bold: model.tod
                                            font.pixelSize: 13 
                                        }
                                    }
                                    
                                    Text { 
                                        anchors.centerIn: parent
                                        visible: model.type === "week"
                                        text: model.d
                                        color: Theme.primary
                                        opacity: 0.3
                                        font.pixelSize: 11 
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true } 
                    }

                    // ── World Clock View ───────────────────────────────────────
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        opacity: root.showWorldClock ? 1.0 : 0.0
                        visible: opacity > 0
                        
                        Behavior on opacity { 
                            NumberAnimation { duration: 250; easing.type: Easing.OutExpo } 
                        }

                        // Search Bar
                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            radius: 16
                            Layout.margins: 10
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.05)
                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                spacing: 6
                                
                                Text { 
                                    text: "󰍉"
                                    color: Theme.primary
                                    opacity: 0.5
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter 
                                }
                                
                                Item {
                                    Layout.fillWidth: true
                                    height: 20
                                    
                                    Text {
                                        anchors.fill: parent
                                        text: "Check time in city..."
                                        color: Theme.primary
                                        opacity: 0.5
                                        font.pixelSize: 12
                                        verticalAlignment: Text.AlignVCenter
                                        visible: wcCityField.text.length === 0
                                    }
                                    
                                    TextInput {
                                        id: wcCityField
                                        anchors.fill: parent
                                        color: Theme.primary
                                        font.pixelSize: 12
                                        verticalAlignment: TextInput.AlignVCenter
                                        onAccepted: loadWcCity(text)
                                        Keys.onEscapePressed: { 
                                            root.showWorldClock = false; 
                                            text = "" 
                                        }
                                    }
                                }
                                
                                Text {
                                    text: "󰅖"
                                    color: Theme.primary
                                    opacity: 0.4
                                    font.pixelSize: 13
                                    visible: wcCityField.text.length > 0
                                    verticalAlignment: Text.AlignVCenter
                                    
                                    MouseArea { 
                                        anchors.fill: parent
                                        onClicked: { 
                                            wcCityField.text = ""
                                            root.targetWcCity = "" 
                                        } 
                                    }
                                }
                            }
                        }

                        // Loading/Error Indicator
                        Item {
                            Layout.fillWidth: true
                            height: 30
                            visible: root.wcLoading || root.wcError !== ""
                            
                            Text { 
                                anchors.centerIn: parent
                                text: root.wcLoading ? "Locating..." : root.wcError
                                color: root.wcError !== "" ? "#ff6b6b" : Theme.primary
                                opacity: 0.6
                                font.pixelSize: 12 
                            }
                        }

                        // Beautiful World Clock Display
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8
                            visible: !root.wcLoading && root.targetWcCity !== ""

                            Item { Layout.fillHeight: true }

                            Text { 
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: root.targetWcCity
                                color: Theme.primary
                                opacity: 0.6
                                font.pixelSize: 20
                                elide: Text.ElideRight
                            }
                            
                            Text { 
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: Qt.formatDateTime(root.worldNow, "HH:mm") 
                                color: Theme.primary
                                font.pixelSize: 84
                                font.weight: Font.Black 
                            }
                            
                            Text { 
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: Qt.formatDateTime(root.worldNow, "dddd, MMMM d") 
                                color: Theme.primary
                                opacity: 0.8
                                font.pixelSize: 18 
                            }
                            
                            Item { Layout.preferredHeight: 12 }
                            
                            // Time Difference Badge
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                height: 28
                                width: timeDiffTxt.implicitWidth + 30
                                radius: 14
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                                border.width: 1
                                
                                Text {
                                    id: timeDiffTxt
                                    anchors.centerIn: parent
                                    text: getWcTimeDiffString()
                                    color: Theme.primary
                                    opacity: 0.7
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }
                            
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }
        }
    }
}