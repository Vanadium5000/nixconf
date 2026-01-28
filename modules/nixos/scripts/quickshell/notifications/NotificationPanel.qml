/*
 * NotificationPanel.qml - Full notification center panel
 */

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../lib"

PanelWindow {
    id: root

    required property var notificationService

    anchors {
        top: true
        right: true
        bottom: true
    }

    margins {
        top: 10
        right: 10
        bottom: 10
    }

    width: 400
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-notification-panel"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    visible: notificationService.panelVisible

    property bool showSettings: false

    GlassPanel {
        id: panel
        anchors.fill: parent
        hasShadow: true
        cornerRadius: Theme.glass.cornerRadius

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.glass.padding
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 100
                    text: root.showSettings ? "Settings" : "Notifications"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeTitle
                    font.bold: true
                    color: Theme.glass.textPrimary
                    elide: Text.ElideRight
                }

                // Notification count badge
                Rectangle {
                    visible: !root.showSettings && root.notificationService.count > 0
                    Layout.preferredWidth: countText.implicitWidth + 16
                    Layout.preferredHeight: 24
                    radius: 12
                    color: Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, 0.3)
                    border.color: Theme.glass.accentColor
                    border.width: 1

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: root.notificationService.count
                        font.family: Theme.glass.fontFamily
                        font.pixelSize: Theme.glass.fontSizeSmall
                        font.bold: true
                        color: Theme.glass.textPrimary
                    }
                }

                // DND toggle
                GlassButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    icon: root.notificationService.dndEnabled ? "󰂛" : "󰂚"
                    active: root.notificationService.dndEnabled
                    cornerRadius: 18
                    onClicked: root.notificationService.toggleDnd()
                }

                // Settings toggle
                GlassButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    icon: "󰒓"
                    active: root.showSettings
                    cornerRadius: 18
                    onClicked: root.showSettings = !root.showSettings
                }

                // Clear all
                GlassButton {
                    visible: !root.showSettings && root.notificationService.count > 0
                    implicitWidth: 36
                    implicitHeight: 36
                    icon: "󰆴"
                    cornerRadius: 18
                    onClicked: root.notificationService.dismissAll()
                }

                // Close panel
                GlassButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    icon: "󰅖"
                    cornerRadius: 18
                    onClicked: root.notificationService.hidePanel()
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.glass.separator
            }

            // Content area
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: root.showSettings ? settingsComponent : notificationListComponent
            }
        }
    }

    // Notification list component
    Component {
        id: notificationListComponent

        Item {
            // Empty state
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.notificationService.count === 0
                spacing: 16

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰂚"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: 64
                    color: Theme.glass.textTertiary
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No notifications"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeLarge
                    color: Theme.glass.textSecondary
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.notificationService.dndEnabled ? "Do Not Disturb is enabled" : "You're all caught up!"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeSmall
                    color: Theme.glass.textTertiary
                }
            }

            // Grouped notification list
            ListView {
                id: groupedList
                anchors.fill: parent
                visible: root.notificationService.count > 0
                spacing: 12
                clip: true

                // Group notifications by app name
                property var groupedModel: {
                    var groups = {}
                    var notifs = root.notificationService.notifications
                    for (var i = 0; i < notifs.length; i++) {
                        var n = notifs[i]
                        var appName = n.appName || "Unknown"
                        if (!groups[appName]) {
                            groups[appName] = {
                                appName: appName,
                                appIcon: n.appIcon,
                                notifications: [],
                                collapsed: false
                            }
                        }
                        groups[appName].notifications.push(n)
                    }
                    // Convert to array and sort by most recent notification
                    var result = Object.values(groups)
                    result.sort((a, b) => {
                        var aTime = a.notifications[0].time
                        var bTime = b.notifications[0].time
                        return bTime - aTime
                    })
                    return result
                }

                model: groupedModel

                delegate: ColumnLayout {
                    id: groupDelegate
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    spacing: 6

                    property bool collapsed: modelData.notifications.length > 2

                    // Group header (only show if more than 1 notification from this app)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: modelData.notifications.length > 1 ? 36 : 0
                        visible: modelData.notifications.length > 1
                        radius: Theme.glass.cornerRadiusSmall
                        color: Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, 0.1)
                        border.color: Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, 0.2)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            // App letter avatar
                            Rectangle {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                radius: 4
                                color: Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, 0.3)

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.appName.charAt(0).toUpperCase()
                                    font.family: Theme.glass.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Theme.glass.accentColor
                                }
                            }

                            // App name
                            Text {
                                Layout.fillWidth: true
                                text: modelData.appName
                                font.family: Theme.glass.fontFamily
                                font.pixelSize: Theme.glass.fontSizeSmall
                                font.bold: true
                                color: Theme.glass.textPrimary
                                elide: Text.ElideRight
                            }

                            // Count badge
                            Rectangle {
                                Layout.preferredWidth: countBadgeText.implicitWidth + 12
                                Layout.preferredHeight: 20
                                radius: 10
                                color: Theme.glass.accentColor

                                Text {
                                    id: countBadgeText
                                    anchors.centerIn: parent
                                    text: modelData.notifications.length
                                    font.family: Theme.glass.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: Theme.glass.textPrimary
                                }
                            }

                            // Expand/collapse button
                            Rectangle {
                                visible: modelData.notifications.length > 2
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 20
                                radius: 4
                                color: "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: groupDelegate.collapsed ? "󰅀" : "󰅃"
                                    font.family: Theme.glass.fontFamily
                                    font.pixelSize: 14
                                    color: Theme.glass.textSecondary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: groupDelegate.collapsed = !groupDelegate.collapsed
                                }
                            }

                            // Dismiss all for this app
                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 20
                                radius: 4
                                color: dismissAllMouse.containsMouse ? Qt.rgba(Theme.colors.red.r, Theme.colors.red.g, Theme.colors.red.b, 0.2) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰆴"
                                    font.family: Theme.glass.fontFamily
                                    font.pixelSize: 12
                                    color: dismissAllMouse.containsMouse ? Theme.colors.red : Theme.glass.textSecondary
                                }

                                MouseArea {
                                    id: dismissAllMouse
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: {
                                        // Dismiss all notifications from this app
                                        var notifs = modelData.notifications
                                        for (var i = 0; i < notifs.length; i++) {
                                            root.notificationService.dismissNotification(notifs[i].id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Notifications in this group
                    Repeater {
                        model: groupDelegate.collapsed ? modelData.notifications.slice(0, 2) : modelData.notifications

                        NotificationItem {
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            notification: modelData
                            isPopup: false

                            onDismissed: root.notificationService.dismissNotification(modelData.id)
                            onActionInvoked: (actionId) => root.notificationService.invokeAction(modelData.id, actionId)
                            onCopyRequested: (text) => root.notificationService.copyToClipboard(text)
                        }
                    }

                    // "Show N more" indicator when collapsed
                    Rectangle {
                        visible: groupDelegate.collapsed && modelData.notifications.length > 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: Theme.glass.cornerRadiusSmall
                        color: Theme.glass.separatorOpaque

                        Text {
                            anchors.centerIn: parent
                            text: "+" + (modelData.notifications.length - 2) + " more notifications"
                            font.family: Theme.glass.fontFamily
                            font.pixelSize: Theme.glass.fontSizeSmall
                            color: Theme.glass.textSecondary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: groupDelegate.collapsed = false
                        }
                    }
                }
            }
        }
    }

    // Settings component
    Component {
        id: settingsComponent

        Flickable {
            contentHeight: settingsColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: settingsColumn
                width: parent.width
                spacing: 16

                // Sound settings section
                Text {
                    text: "Sound Settings"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeLarge
                    font.bold: true
                    color: Theme.glass.textPrimary
                }

                // Volume slider row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "Volume"
                        font.family: Theme.glass.fontFamily
                        font.pixelSize: Theme.glass.fontSizeMedium
                        color: Theme.glass.textSecondary
                    }

                    // Custom slider
                    Item {
                        id: volumeSlider
                        Layout.fillWidth: true
                        implicitHeight: 20

                        property real value: root.notificationService.soundVolume

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 4
                            radius: 2
                            color: Theme.glass.separatorOpaque

                            Rectangle {
                                width: volumeSlider.value * parent.width
                                height: parent.height
                                radius: 2
                                color: Theme.glass.accentColor
                            }
                        }

                        Rectangle {
                            x: volumeSlider.value * (parent.width - width)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 16
                            radius: 8
                            color: volumeSliderMouse.pressed ? Theme.glass.accentColorAlt : Theme.glass.textPrimary
                            border.color: Theme.glass.accentColor
                            border.width: 2
                        }

                        MouseArea {
                            id: volumeSliderMouse
                            anchors.fill: parent
                            onPressed: (mouse) => updateValue(mouse)
                            onPositionChanged: (mouse) => { if (pressed) updateValue(mouse) }

                            function updateValue(mouse) {
                                var pos = Math.max(0, Math.min(1, mouse.x / width))
                                volumeSlider.value = pos
                                root.notificationService.soundVolume = pos
                                root.notificationService.saveSettings()
                            }
                        }
                    }

                    Text {
                        text: Math.round(volumeSlider.value * 100) + "%"
                        font.family: Theme.glass.fontFamily
                        font.pixelSize: Theme.glass.fontSizeSmall
                        color: Theme.glass.textTertiary
                        Layout.preferredWidth: 40
                    }
                }

                // Test sound button
                GlassButton {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    text: "Test Sound"
                    icon: "󰕾"
                    cornerRadius: Theme.glass.cornerRadiusSmall
                    contentAlignment: Qt.AlignHCenter
                    onClicked: root.notificationService.playDing()
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.glass.separator
                }

                // Urgency settings
                Text {
                    text: "Play Sound For"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeLarge
                    font.bold: true
                    color: Theme.glass.textPrimary
                }

                // Low urgency toggle
                SettingsToggle {
                    Layout.fillWidth: true
                    label: "Low Priority"
                    description: "Quiet notifications"
                    checked: root.notificationService.dingSoundSettings["low"] ?? false
                    onToggled: root.notificationService.setDingForUrgency("low", checked)
                }

                // Normal urgency toggle
                SettingsToggle {
                    Layout.fillWidth: true
                    label: "Normal Priority"
                    description: "Standard notifications"
                    checked: root.notificationService.dingSoundSettings["normal"] ?? true
                    onToggled: root.notificationService.setDingForUrgency("normal", checked)
                }

                // Critical urgency toggle
                SettingsToggle {
                    Layout.fillWidth: true
                    label: "Critical Priority"
                    description: "Urgent notifications"
                    checked: root.notificationService.dingSoundSettings["critical"] ?? true
                    onToggled: root.notificationService.setDingForUrgency("critical", checked)
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 8
                    color: Theme.glass.separator
                }

                // Regex patterns section
                Text {
                    text: "Always Ding Patterns"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeLarge
                    font.bold: true
                    color: Theme.glass.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    text: "Regex patterns matching app name or summary"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeSmall
                    color: Theme.glass.textTertiary
                    wrapMode: Text.Wrap
                }

                // Add pattern input
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: Theme.glass.cornerRadiusSmall
                        color: Theme.glass.separatorOpaque
                        border.color: patternInput.activeFocus ? Theme.glass.accentColor : Theme.glass.separator
                        border.width: 1

                        TextInput {
                            id: patternInput
                            anchors.fill: parent
                            anchors.margins: 8
                            font.family: Theme.glass.fontFamily
                            font.pixelSize: Theme.glass.fontSizeMedium
                            color: Theme.glass.textPrimary
                            clip: true
                            verticalAlignment: TextInput.AlignVCenter

                            property string placeholderText: "e.g. OpenCode.*"

                            Text {
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !patternInput.text && !patternInput.activeFocus
                                text: patternInput.placeholderText
                                font: patternInput.font
                                color: Theme.glass.textTertiary
                                verticalAlignment: Text.AlignVCenter
                            }

                            onAccepted: {
                                if (text.trim() !== "") {
                                    root.notificationService.addDingPattern(text.trim())
                                    text = ""
                                }
                            }
                        }
                    }

                    GlassButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        icon: "󰐕"
                        cornerRadius: Theme.glass.cornerRadiusSmall
                        onClicked: {
                            if (patternInput.text.trim() !== "") {
                                root.notificationService.addDingPattern(patternInput.text.trim())
                                patternInput.text = ""
                            }
                        }
                    }
                }

                // Pattern list
                Repeater {
                    model: root.notificationService.dingPatterns

                    RowLayout {
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: Theme.glass.cornerRadiusSmall
                            color: Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, 0.1)
                            border.color: Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, 0.3)
                            border.width: 1

                            Text {
                                anchors.fill: parent
                                anchors.margins: 8
                                text: modelData
                                font.family: Theme.glass.fontFamily
                                font.pixelSize: Theme.glass.fontSizeSmall
                                color: Theme.glass.textPrimary
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        GlassButton {
                            implicitWidth: 28
                            implicitHeight: 28
                            icon: "󰅖"
                            cornerRadius: 14
                            onClicked: root.notificationService.removeDingPattern(modelData)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 8
                    color: Theme.glass.separator
                }

                // Per-app ding overrides section
                Text {
                    text: "Per-App Sound Settings"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeLarge
                    font.bold: true
                    color: Theme.glass.textPrimary
                }

                Text {
                    Layout.fillWidth: true
                    text: "Override sound settings for specific apps"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeSmall
                    color: Theme.glass.textTertiary
                    wrapMode: Text.Wrap
                }

                // Get unique app names from notifications
                Repeater {
                    id: appOverridesRepeater
                    model: {
                        // Get unique app names from current notifications
                        var apps = {}
                        var notifs = root.notificationService.notifications
                        for (var i = 0; i < notifs.length; i++) {
                            var appName = notifs[i].appName
                            if (appName && appName !== "") {
                                apps[appName] = true
                            }
                        }
                        // Also include any already-overridden apps
                        var overrides = root.notificationService.appDingOverrides
                        for (var app in overrides) {
                            apps[app] = true
                        }
                        return Object.keys(apps).sort()
                    }

                    RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        spacing: 8

                        // App letter avatar
                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 6
                            color: Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, 0.2)
                            border.color: Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, 0.4)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.charAt(0).toUpperCase()
                                font.family: Theme.glass.fontFamily
                                font.pixelSize: 12
                                font.bold: true
                                color: Theme.glass.accentColor
                            }
                        }

                        // App name
                        Text {
                            Layout.fillWidth: true
                            text: modelData
                            font.family: Theme.glass.fontFamily
                            font.pixelSize: Theme.glass.fontSizeMedium
                            color: Theme.glass.textPrimary
                            elide: Text.ElideRight
                        }

                        // Three-state toggle: Default / On / Off
                        Row {
                            spacing: 4

                            property var currentState: {
                                var overrides = root.notificationService.appDingOverrides
                                if (modelData in overrides) {
                                    return overrides[modelData] ? "on" : "off"
                                }
                                return "default"
                            }

                            // Default button
                            Rectangle {
                                width: 28
                                height: 24
                                radius: 6
                                color: parent.currentState === "default" ? Theme.glass.accentColor : Theme.glass.separatorOpaque
                                border.color: parent.currentState === "default" ? Theme.glass.accentColor : Theme.glass.separator
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "D"
                                    font.family: Theme.glass.fontFamily
                                    font.pixelSize: 10
                                    font.bold: true
                                    color: parent.parent.currentState === "default" ? Theme.glass.textPrimary : Theme.glass.textTertiary
                                }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            // Remove override to use default
                                            var overrides = root.notificationService.appDingOverrides
                                            delete overrides[modelData]
                                            root.notificationService.appDingOverrides = Object.assign({}, overrides)
                                            root.notificationService.saveSettings()
                                        }
                                    }
                                }

                            // On button
                            Rectangle {
                                width: 28
                                height: 24
                                radius: 6
                                color: parent.currentState === "on" ? Theme.colors.green : Theme.glass.separatorOpaque
                                border.color: parent.currentState === "on" ? Theme.colors.green : Theme.glass.separator
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰂚"
                                    font.family: Theme.glass.fontFamily
                                    font.pixelSize: 12
                                    color: parent.parent.currentState === "on" ? Theme.glass.textPrimary : Theme.glass.textTertiary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.notificationService.setDingForApp(modelData, true)
                                }
                            }

                            // Off button
                            Rectangle {
                                width: 28
                                height: 24
                                radius: 6
                                color: parent.currentState === "off" ? Theme.colors.red : Theme.glass.separatorOpaque
                                border.color: parent.currentState === "off" ? Theme.colors.red : Theme.glass.separator
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰂛"
                                    font.family: Theme.glass.fontFamily
                                    font.pixelSize: 12
                                    color: parent.parent.currentState === "off" ? Theme.glass.textPrimary : Theme.glass.textTertiary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.notificationService.setDingForApp(modelData, false)
                                }
                            }
                        }
                    }
                }

                // Empty state for per-app settings
                Text {
                    visible: appOverridesRepeater.count === 0
                    Layout.fillWidth: true
                    text: "No apps with notifications yet"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeSmall
                    font.italic: true
                    color: Theme.glass.textTertiary
                    horizontalAlignment: Text.AlignHCenter
                }

                // Spacer
                Item { Layout.fillHeight: true }
            }
        }
    }

    // Settings toggle component
    component SettingsToggle: RowLayout {
        property string label: ""
        property string description: ""
        property bool checked: false
        signal toggled()

        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: label
                font.family: Theme.glass.fontFamily
                font.pixelSize: Theme.glass.fontSizeMedium
                color: Theme.glass.textPrimary
            }

            Text {
                visible: description !== ""
                text: description
                font.family: Theme.glass.fontFamily
                font.pixelSize: Theme.glass.fontSizeSmall
                color: Theme.glass.textTertiary
            }
        }

        // Toggle switch
        Rectangle {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 28
            radius: 14
            color: checked ? Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, 0.3) : Theme.glass.separatorOpaque
            border.color: checked ? Theme.glass.accentColor : Theme.glass.separator
            border.width: 1

            Rectangle {
                x: checked ? parent.width - width - 4 : 4
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                radius: 10
                color: checked ? Theme.glass.accentColor : Theme.glass.textTertiary

                Behavior on x {
                    NumberAnimation { duration: Theme.glass.animationDuration }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    checked = !checked
                    toggled()
                }
            }
        }
    }

    // Close on Escape
    Shortcut {
        sequence: "Escape"
        onActivated: root.notificationService.hidePanel()
    }
}
