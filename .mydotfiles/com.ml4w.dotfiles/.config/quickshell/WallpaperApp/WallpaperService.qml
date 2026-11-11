pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared state for the wallpaper grid (WallpaperWindow) and the carousel
// (WallpaperCarousel): the wallpaper folder, the current wallpaper and the
// call that applies a wallpaper.
Singleton {
    id: root

    property string defaultWallpaperFolder: Quickshell.env("HOME") + "/.config/ml4w/wallpapers"
    property string wallpaperSettingFile: Quickshell.env("HOME") + "/.config/ml4w/settings/wallpaper-folder"
    property string currentWallpaperFile: Quickshell.env("HOME") + "/.cache/ml4w/hyprland-dotfiles/current_wallpaper"
    property string wallpaperScript: Quickshell.env("HOME") + "/.config/ml4w/scripts/ml4w-wallpaper"

    // Start as default in case file does not exist
    property string wallpaperFolder: defaultWallpaperFolder

    // --- Video wallpapers (see ~/.config/hypr/conf/custom/video-wallpaper.sh) ---
    property string videoScript: Quickshell.env("HOME") + "/.config/hypr/conf/custom/video-wallpaper.sh"
    property string posterDir: Quickshell.env("HOME") + "/.cache/video-wallpapers/posters"
    readonly property var imageExts: ["jpg", "jpeg", "png"]
    readonly property var videoExts: ["mp4", "webm", "mkv", "mov", "m4v"]
    // Bumped when posters were (re)generated so thumbnails reload
    property int posterRevision: 0

    onWallpaperFolderChanged: if (wallpaperFolder !== "") posterJob.refresh()

    // Raw text of the folder setting, as shown in the advanced options
    property string wallpaperFolderSetting: ""

    // Path of the wallpaper last applied with theming. May point to an
    // effect copy in the cache ("<effect>-<name>"), so match on file name.
    property string currentWallpaper: ""

    FileView {
        id: wallpaperDirSettingFileHandler
        path: Qt.url(root.wallpaperSettingFile)
        blockLoading: true
        watchChanges: true
        onFileChanged: {
            this.reload();
            const settingValue = this.text().trim()
            console.log("Wallpaper directory setting changed on disk; attempting to load directory \"" + settingValue + "\"")
            root.updateWallpaperFolder(settingValue)
        }
        onLoaded: {
            const settingValue = this.text().trim()
            console.log("Loading wallpaper directory \"" + settingValue + "\"")
            root.updateWallpaperFolder(settingValue)
        }
        onSaved: {
            const settingValue = this.text().trim()
            console.log("Wallpaper directory setting saved successfully; reloading from directory \"" + settingValue + "\"")
            root.updateWallpaperFolder(settingValue)
        }
    }

    FileView {
        id: currentWallpaperFileHandler
        path: Qt.url(root.currentWallpaperFile)
        watchChanges: true
        printErrors: false
        onFileChanged: this.reload()
        onLoaded: root.currentWallpaper = this.text().trim()
    }

    function updateWallpaperFolder(dirString): void {
        root.wallpaperFolderSetting = dirString
        root.wallpaperFolder = dirString.replace(/~|\$HOME/g, Quickshell.env("HOME"))
    }

    function setWallpaperFolder(dirString): void {
        console.log("Updating wallpaper directory to \"" + dirString + "\"")
        wallpaperDirSettingFileHandler.setText(dirString)
    }

    // Blank the folder and set it back so every FolderListModel rescans it
    function reloadImages(): void {
        const current = root.wallpaperFolder
        root.wallpaperFolder = ""
        Qt.callLater(() => { root.wallpaperFolder = current })
    }

    // True when fileName is the current wallpaper (or an effect copy of it)
    function isCurrent(fileName): bool {
        if (root.currentWallpaper === "" || fileName === "")
            return false
        const current = root.currentWallpaper.substring(root.currentWallpaper.lastIndexOf("/") + 1)
        return current === fileName || current.endsWith("-" + fileName)
    }

    function isVideo(path): bool {
        const dot = path.lastIndexOf(".")
        return dot >= 0 && root.videoExts.indexOf(path.substring(dot + 1).toLowerCase()) >= 0
    }

    // FolderListModel name filters for images and videos, optionally narrowed by a search term
    function nameFilters(search): var {
        const s = (search || "").trim()
        return root.imageExts.concat(root.videoExts).map(e => "*" + s + (s === "" ? "" : "*") + "." + e)
    }

    // URL to show for a wallpaper: the file itself, or a video's cached poster frame
    // (same name the shell script uses: md5 of the path). The fragment forces a reload
    // after posters are regenerated.
    function thumb(path): string {
        if (!path)
            return ""
        if (!root.isVideo(path))
            return "file://" + path
        return "file://" + root.posterDir + "/" + Qt.md5(path) + ".jpg#" + root.posterRevision
    }

    // Make posters for videos added to the folder since the last scan
    function refreshPosters(): void {
        if (root.wallpaperFolder !== "")
            posterJob.refresh()
    }

    Process {
        id: posterJob
        property bool pending: false
        function refresh(): void {
            if (running) { pending = true; return }
            command = [root.videoScript, "posters", root.wallpaperFolder]
            running = true
        }
        onExited: {
            root.posterRevision++
            if (pending) { pending = false; refresh() }
        }
    }

    // Pass each value as its own argument. No shell reads the
    // file name, so quotes and spaces in it are safe.
    function apply(filePath, extraArgs): void {
        Quickshell.execDetached([root.wallpaperScript, filePath].concat(extraArgs || []))
    }
}
