import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string statusClass: "inactive"
    property bool isEnabled: false
    property bool isActive: false
    property bool isBusy: false
    property string tooltip: "Idle inhibitor is disabled"
    readonly property int refreshInterval: 5000
    readonly property string inhibitCommand: "__DMS_IDLE_INHIBIT__"

    readonly property string statusIcon: root.isBusy ? "hourglass_empty" : (root.isEnabled ? "visibility_off" : "visibility")
    readonly property color statusColor: root.isEnabled ? (root.isActive ? Theme.primary : Theme.warning) : Theme.widgetIconColor

    pillClickAction: () => root.toggleInhibit()

    function applyStatus(output) {
        try {
            const data = JSON.parse((output || "").trim())
            root.statusClass = data.class || "inactive"
            root.isEnabled = data.enabled === true || root.statusClass === "active" || root.statusClass === "starting"
            root.isActive = data.active === true || root.statusClass === "active"
            root.tooltip = data.tooltip || (root.isEnabled ? "Idle inhibitor is enabled" : "Idle inhibitor is disabled")
        } catch (error) {
            root.statusClass = "inactive"
            root.isEnabled = false
            root.isActive = false
            root.tooltip = "Idle inhibitor status could not be read"
            console.warn("IdleInhibit: failed to parse status", error)
        }
    }

    function refreshStatus() {
        if (statusProcess.running || toggleProcess.running)
            return
        statusProcess.running = true
    }

    function toggleInhibit() {
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
                console.warn("IdleInhibit: status command failed with code", exitCode)
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
                console.warn("IdleInhibit: toggle command failed with code", exitCode)
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
