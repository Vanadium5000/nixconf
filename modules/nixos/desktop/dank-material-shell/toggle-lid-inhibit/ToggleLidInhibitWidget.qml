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
    property string tooltip: "Lid suspend inhibitor is disabled"
    readonly property int refreshInterval: 30000
    readonly property string inhibitCommand: "__TOGGLE_LID_INHIBIT__"

    readonly property string statusIcon: root.isBusy ? "hourglass_empty" : (root.isActive ? "lock_open" : "lock")
    readonly property color statusColor: root.isActive ? Theme.primary : Theme.widgetIconColor

    pillClickAction: () => root.toggleLidInhibit()

    function applyStatus(output) {
        try {
            const data = JSON.parse((output || "").trim())
            root.statusClass = data.class || "inactive"
            root.isActive = data.active === true || root.statusClass === "active"
            root.tooltip = data.tooltip || (root.isActive ? "Lid suspend inhibitor is enabled" : "Lid suspend inhibitor is disabled")
        } catch (error) {
            root.statusClass = "inactive"
            root.isActive = false
            root.tooltip = "Lid suspend inhibitor status could not be read"
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

    Component.onCompleted: refreshStatus()

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Process {
        id: statusProcess
        command: [root.inhibitCommand, "status"]
        running: false

        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: root.applyStatus(statusCollector.text)
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("ToggleLidInhibit: status command failed with code", exitCode)
        }
    }

    Process {
        id: toggleProcess
        command: [root.inhibitCommand, "toggle"]
        running: false

        stdout: StdioCollector {
            id: toggleCollector
            onStreamFinished: root.applyStatus(toggleCollector.text)
        }

        onExited: exitCode => {
            root.isBusy = false
            if (exitCode !== 0)
                console.warn("ToggleLidInhibit: toggle command failed with code", exitCode)
            root.refreshStatus()
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: icon.width
            implicitHeight: root.widgetThickness

            DankIcon {
                id: icon
                name: root.statusIcon
                size: Theme.barIconSize(root.barThickness, -4)
                color: root.statusColor
                anchors.centerIn: parent
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: root.widgetThickness
            implicitHeight: icon.height

            DankIcon {
                id: icon
                name: root.statusIcon
                size: Theme.barIconSize(root.barThickness)
                color: root.statusColor
                anchors.centerIn: parent
            }
        }
    }
}
