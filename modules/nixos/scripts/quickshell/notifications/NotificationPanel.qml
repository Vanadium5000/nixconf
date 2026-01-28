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
                    text: root.showSettings ? "Settings" : "Notifications"
                    font.family: Theme.glass.fontFamily
                    font.pixelSize: Theme.glass.fontSizeTitle
                    font.bold: true
                    color: Theme.glass.textPrimary
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

            // Notification list
            ListView {
                anchors.fill: parent
                visible: root.notificationService.count > 0
                spacing: 8
                clip: true

                model: root.notificationService.notifications

                delegate: NotificationItem {
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    notification: modelData
                    isPopup: false

                    onDismissed: root.notificationService.dismissNotification(modelData.id)
                    onActionInvoked: (actionId) => root.notificationService.invokeAction(modelData.id, actionId)
                    onCopyRequested: (text) => root.notificationService.copyToClipboard(text)
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
