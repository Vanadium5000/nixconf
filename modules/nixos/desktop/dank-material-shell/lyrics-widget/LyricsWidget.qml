import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property string lyricsCommand: "__LYRICSCTL__"
    readonly property int refreshInterval: 500
    readonly property int contextLines: 10

    property string lyricText: "♪"
    property string title: "No player"
    property string artist: ""
    property string album: ""
    property string player: ""
    property string status: "Stopped"
    property string statusClass: "stopped"
    property bool synced: false
    property bool compactText: false
    property bool commandBusy: false
    property var lines: []

    readonly property bool isPlaying: status === "Playing"
    readonly property string statusIcon: status === "Playing" ? "pause" : (status === "Paused" ? "play_arrow" : "music_note")
    readonly property color statusColor: statusClass === "playing" ? Theme.primary : (statusClass === "no-lyrics" ? Theme.warning : Theme.surfaceVariantText)
    readonly property string headerText: title + (artist.length > 0 ? " — " + artist : "")

    popoutWidth: 440

    function commandLine(args) {
        return [root.lyricsCommand].concat(args || [])
    }

    function refreshStatus() {
        if (!statusProcess.running)
            statusProcess.running = true
    }

    function runControl(action) {
        if (controlProcess.running)
            return
        root.commandBusy = true
        controlProcess.command = root.commandLine(["control", action])
        controlProcess.running = true
    }

    function runOverlay(action) {
        if (overlayProcess.running)
            return
        root.commandBusy = true
        overlayProcess.command = root.commandLine([action, "--lines", "4"])
        overlayProcess.running = true
    }

    function loadSettings() {
        if (!pluginService || !pluginService.loadPluginData)
            return
        compactText = pluginService.loadPluginData("lyricsWidget", "compactText", false) === true
    }

    function saveSetting(key, value) {
        if (pluginService && pluginService.savePluginData)
            pluginService.savePluginData("lyricsWidget", key, value)
    }

    function safeText(value, fallback) {
        const text = String(value || "").trim()
        return text.length > 0 ? text : fallback
    }

    function parseStatus(output) {
        try {
            const data = JSON.parse((output || "").trim())
            root.lyricText = root.safeText(data.text || data.current, data.status === "Stopped" ? "" : "♪")
            root.title = root.safeText(data.title, "No player")
            root.artist = root.safeText(data.artist, "")
            root.album = root.safeText(data.album, "")
            root.player = root.safeText(data.player, "")
            root.status = root.safeText(data.status, "Stopped")
            root.statusClass = root.safeText(data.class, "stopped")
            root.synced = data.synced === true
            root.lines = Array.isArray(data.lines) ? data.lines.slice(0, root.contextLines) : []
        } catch (error) {
            root.lyricText = ""
            root.title = "Lyrics unavailable"
            root.artist = ""
            root.album = ""
            root.player = ""
            root.status = "Stopped"
            root.statusClass = "error"
            root.synced = false
            root.lines = []
            console.warn("LyricsWidget: failed to parse status", error)
        }
    }

    Component.onCompleted: {
        loadSettings()
        refreshStatus()
    }

    onPluginServiceChanged: loadSettings()

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Process {
        id: statusProcess
        command: root.commandLine(["status", "--lines", root.contextLines.toString(), "--length", "96"])
        running: false

        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: root.parseStatus(statusCollector.text)
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("LyricsWidget: status command failed", exitCode)
        }
    }

    Process {
        id: controlProcess
        running: false
        onExited: exitCode => {
            root.commandBusy = false
            if (exitCode !== 0)
                console.warn("LyricsWidget: control command failed", exitCode)
            root.refreshStatus()
        }
    }

    Process {
        id: overlayProcess
        running: false
        onExited: exitCode => {
            root.commandBusy = false
            if (exitCode !== 0)
                console.warn("LyricsWidget: overlay command failed", exitCode)
            root.refreshStatus()
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: barRow.implicitWidth
            implicitHeight: root.widgetThickness

            Row {
                id: barRow
                spacing: Theme.spacingXS
                anchors.centerIn: parent

                DankIcon {
                    name: root.compactText ? "lyrics" : root.statusIcon
                    size: Theme.barIconSize(root.barThickness, -4)
                    color: root.statusColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.compactText ? "♪" : (root.lyricText.length > 0 ? root.lyricText : root.statusIcon)
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.statusColor
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    visible: root.barConfig?.maximizeWidgetText ?? true
                    width: root.compactText ? implicitWidth : Math.min(implicitWidth, 220)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: root.widgetThickness
            implicitHeight: icon.height

            DankIcon {
                id: icon
                name: root.compactText ? "lyrics" : root.statusIcon
                size: Theme.barIconSize(root.barThickness)
                color: root.statusColor
                anchors.centerIn: parent
            }
        }
    }

    popoutContent: Component {
        Column {
            spacing: Theme.spacingM

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                DankIcon {
                    name: root.statusIcon
                    size: Theme.iconSizeLarge
                    color: root.statusColor
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: root.headerText
                        font.pixelSize: Theme.fontSizeXLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: (root.album.length > 0 ? root.album + " · " : "") + root.status + (root.synced ? " · synced lyrics" : " · no synced lyrics")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                DankActionButton {
                    buttonSize: 32
                    iconName: "refresh"
                    iconColor: Theme.surfaceVariantText
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.refreshStatus()
                }
            }

            StyledRect {
                width: parent.width
                height: lyricsColumn.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: lyricsColumn
                    width: parent.width - Theme.spacingM * 2
                    x: Theme.spacingM
                    y: Theme.spacingM
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Lyrics"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    Repeater {
                        model: root.lines.length > 0 ? root.lines : [root.lyricText.length > 0 ? root.lyricText : "No lyrics available"]

                        delegate: StyledText {
                            required property int index
                            required property var modelData

                            width: parent.width
                            text: modelData
                            font.pixelSize: index === 0 ? Theme.fontSizeMedium : Theme.fontSizeSmall
                            font.weight: index === 0 ? Font.Medium : Font.Normal
                            color: index === 0 ? Theme.primary : Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            RowLayout {
                width: parent.width
                spacing: Theme.spacingS

                DankActionButton {
                    buttonSize: 36
                    iconName: "skip_previous"
                    iconColor: Theme.surfaceVariantText
                    enabled: !root.commandBusy
                    onClicked: root.runControl("previous")
                }

                DankButton {
                    text: root.isPlaying ? "Pause" : "Play"
                    iconName: root.isPlaying ? "pause" : "play_arrow"
                    backgroundColor: Theme.primary
                    textColor: Theme.primaryText
                    enabled: !root.commandBusy
                    Layout.fillWidth: true
                    onClicked: root.runControl("play-pause")
                }

                DankActionButton {
                    buttonSize: 36
                    iconName: "skip_next"
                    iconColor: Theme.surfaceVariantText
                    enabled: !root.commandBusy
                    onClicked: root.runControl("next")
                }
            }

            RowLayout {
                width: parent.width
                spacing: Theme.spacingS

                DankButton {
                    text: "Overlay"
                    iconName: "open_in_full"
                    backgroundColor: Theme.surfaceContainerHigh
                    textColor: Theme.surfaceText
                    enabled: !root.commandBusy
                    Layout.fillWidth: true
                    onClicked: root.runOverlay("toggle")
                }

                DankButton {
                    text: "Hide overlay"
                    iconName: "close_fullscreen"
                    backgroundColor: Theme.surfaceContainerHigh
                    textColor: Theme.surfaceText
                    enabled: !root.commandBusy
                    Layout.fillWidth: true
                    onClicked: root.runOverlay("hide")
                }
            }

            DankToggle {
                width: parent.width
                text: "Compact bar text"
                description: "Show only a small music glyph in the bar while keeping this menu on click."
                checked: root.compactText
                onToggled: checked => {
                    root.compactText = checked
                    root.saveSetting("compactText", checked)
                }
            }
        }
    }
}
