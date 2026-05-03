import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string statusClass: "inactive"
    property bool isActive: false
    property bool isBusy: false
    readonly property int refreshInterval: 30000
    readonly property string statusCommand: "__LID_STATUS__"
    readonly property string toggleCommand: "__TOGGLE_LID_INHIBIT__"

    readonly property string statusLabel: root.isBusy ? "..." : (root.isActive ? "On" : "Off")

    pillClickAction: () => root.toggleLidInhibit()

    function applyStatus(output) {
        try {
            const data = JSON.parse((output || "").trim())
            root.statusClass = data.class || "inactive"
            root.isActive = root.statusClass === "active"
        } catch (error) {
            root.statusClass = "inactive"
            root.isActive = false
            console.warn("ToggleLidInhibit: failed to parse status", error)
        }
    }

    function refreshStatus() {
        if (statusProcess.running || toggleProcess.running)
            return
        statusProcess.running = true
    }

    function toggleLidInhibit() {
        if (toggleProcess.running)
            return
        root.isBusy = true
        toggleProcess.running = true
    }

    Component.onCompleted: {
        refreshStatus()
    }

    Timer {
        id: refreshTimer
        interval: root.refreshInterval
        running: true
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Process {
        id: statusProcess
        command: [root.statusCommand]
        running: false

        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: {
                root.applyStatus(statusCollector.text)
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn("ToggleLidInhibit: status command failed with code", exitCode)
            }
        }
    }

    Process {
        id: toggleProcess
        command: [root.toggleCommand]
        running: false

        onExited: exitCode => {
            root.isBusy = false
            if (exitCode !== 0) {
                console.warn("ToggleLidInhibit: toggle command failed with code", exitCode)
            }
            root.refreshStatus()
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.isActive ? "lock_open" : "lock"
                size: Theme.barIconSize(root.barThickness, -4)
                color: root.isActive ? Theme.primary : Theme.widgetIconColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.statusLabel
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                color: root.isActive ? Theme.primary : Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 1

            DankIcon {
                name: root.isActive ? "lock_open" : "lock"
                size: Theme.barIconSize(root.barThickness)
                color: root.isActive ? Theme.primary : Theme.widgetIconColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.statusLabel
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                color: root.isActive ? Theme.primary : Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
