pragma Singleton
import QtQuick

// Single source of truth for the navigation list and the search index.
// `pages` drives the sidebar; `searchIndex` lets the search box jump to an
// individual setting and highlights the page that owns it.
QtObject {
    id: root

    // Order matches the layout the user asked for.
    readonly property var pages: [
        { id: "wifi",       title: "Wi-Fi",       icon: "󰤨", keywords: "wifi wireless network ssid signal hotspot" },
        { id: "network",    title: "Network",     icon: "󰦝", keywords: "network vpn openvpn surfshark wireguard ethernet proxy connection dns" },
        { id: "firewall",   title: "Firewall",    icon: "󰕥", keywords: "firewall ufw rules ports allow deny block security incoming" },
        { id: "bluetooth",  title: "Bluetooth",   icon: "󰂯", keywords: "bluetooth pair device headphones audio" },
        { id: "displays",   title: "Displays",    icon: "󰍹", keywords: "display monitor screen resolution refresh scale rotation arrangement" },
        { id: "sound",      title: "Sound",       icon: "󰕾", keywords: "sound audio volume output input microphone speaker mute device" },
        { id: "power",      title: "Power",       icon: "󰂄", keywords: "power battery profile performance saver suspend sleep" },
        { id: "appearance", title: "Appearance",  icon: "󰸉", keywords: "appearance wallpaper background theme look transition" },
        { id: "keyboard",   title: "Keyboard",    icon: "󰌌", keywords: "keyboard layout variant input language repeat" },
        { id: "printers",   title: "Printers",    icon: "󰐪", keywords: "printer print cups queue scanner" },
        { id: "system",     title: "System",      icon: "󰒓", keywords: "system about info hostname kernel os cpu memory uptime" }
    ]

    // Flat index of individual, searchable settings. `page` ties a hit back to
    // its owning page id above.
    readonly property var searchIndex: [
        { page: "wifi",       title: "Wi-Fi",                 keywords: "enable disable toggle wireless radio" },
        { page: "wifi",       title: "Available networks",    keywords: "scan connect ssid join password" },
        { page: "network",    title: "VPN",                   keywords: "vpn openvpn wireguard connect tunnel" },
        { page: "network",    title: "Surfshark / VPN apps",  keywords: "surfshark proton mullvad nord launch app" },
        { page: "network",    title: "Wired / Ethernet",      keywords: "ethernet wired lan cable" },
        { page: "network",    title: "OpenVPN connections",   keywords: "openvpn config connect edit add cli tunnel" },
        { page: "firewall",   title: "Firewall",              keywords: "ufw enable disable status security toggle" },
        { page: "firewall",   title: "Firewall rules",        keywords: "add delete allow deny port rule incoming" },
        { page: "bluetooth",  title: "Bluetooth power",       keywords: "enable disable toggle radio" },
        { page: "bluetooth",  title: "Devices",               keywords: "pair connect device manager" },
        { page: "displays",   title: "Resolution & refresh",  keywords: "mode resolution refresh rate hz" },
        { page: "displays",   title: "Scale",                 keywords: "scaling dpi hidpi" },
        { page: "displays",   title: "Orientation",           keywords: "rotation transform portrait landscape" },
        { page: "displays",   title: "Arrangement",           keywords: "position layout multiple monitors" },
        { page: "sound",      title: "Output volume",         keywords: "volume speaker level mute" },
        { page: "sound",      title: "Output device",         keywords: "sink speaker headphones device" },
        { page: "sound",      title: "Input volume",          keywords: "microphone mic record level" },
        { page: "sound",      title: "Input device",          keywords: "source microphone device" },
        { page: "power",      title: "Power profile",         keywords: "performance balanced saver powerprofiles" },
        { page: "power",      title: "Battery",               keywords: "battery charge percentage" },
        { page: "power",      title: "Suspend & power off",   keywords: "sleep suspend shutdown reboot logout" },
        { page: "appearance", title: "Wallpaper",             keywords: "background image picture wallpaper" },
        { page: "appearance", title: "Transition effect",     keywords: "animation transition fade slide" },
        { page: "keyboard",   title: "Keyboard layout",       keywords: "layout variant language us fr de" },
        { page: "printers",   title: "Printers",              keywords: "printer cups queue add" },
        { page: "system",     title: "About this system",     keywords: "hostname kernel os distro version" },
        { page: "system",     title: "Hardware",              keywords: "cpu memory ram gpu uptime" }
    ]

    function pageById(id) {
        for (var i = 0; i < pages.length; i++)
            if (pages[i].id === id) return pages[i]
        return pages[0]
    }

    function pageIndex(id) {
        for (var i = 0; i < pages.length; i++)
            if (pages[i].id === id) return i
        return 0
    }

    // Returns search hits: matching pages first, then individual settings.
    function search(query) {
        var q = (query || "").trim().toLowerCase()
        if (q === "") return []
        var hits = []
        for (var i = 0; i < pages.length; i++) {
            var p = pages[i]
            if (p.title.toLowerCase().indexOf(q) !== -1 || p.keywords.indexOf(q) !== -1)
                hits.push({ page: p.id, title: p.title, sub: "", icon: p.icon, isPage: true })
        }
        for (var j = 0; j < searchIndex.length; j++) {
            var s = searchIndex[j]
            if (s.title.toLowerCase().indexOf(q) !== -1 || s.keywords.indexOf(q) !== -1) {
                var owner = pageById(s.page)
                hits.push({ page: s.page, title: s.title, sub: owner.title, icon: owner.icon, isPage: false })
            }
        }
        return hits
    }
}
