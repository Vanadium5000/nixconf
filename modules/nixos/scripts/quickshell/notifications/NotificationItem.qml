/*
 * NotificationItem.qml - Individual notification display component
 */

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../lib"

GlassPanel {
    id: root

    required property var notification
    property bool isPopup: false
    property bool expanded: false

    signal dismissed()
    signal actionInvoked(string actionId)
    signal copyRequested(string text)

    implicitHeight: contentColumn.implicitHeight + Theme.glass.padding * 2
    cornerRadius: Theme.glass.cornerRadiusSmall
    hasShadow: isPopup

    // Swipe gesture handling
    property real dragX: 0
    property real dragThreshold: 100

    transform: Translate { x: root.dragX }

    Behavior on dragX {
        NumberAnimation {
            duration: Theme.glass.animationDuration
            easing.type: Easing.OutCubic
        }
    }

    // Urgency-based accent
    property color urgencyColor: {
        if (root.notification.urgency === 2) return Theme.colors.red
        if (root.notification.urgency === 0) return Theme.colors.base04
        return Theme.glass.accentColor
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: Theme.glass.padding
        spacing: 8

        // Header row: icon, app name, time, close button
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // App icon
            Item {
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24

                IconImage {
                    id: appIcon
                    anchors.fill: parent
                    
                    property string resolvedIcon: {
                        if (!root.notification.appIcon || root.notification.appIcon === "") {
                            return Quickshell.iconPath("dialog-information", "")
                        }
                        if (root.notification.appIcon.startsWith("/")) {
                            return "file://" + root.notification.appIcon
                        }
                        var resolved = Quickshell.iconPath(root.notification.appIcon, "")
                        return resolved !== "" ? resolved : Quickshell.iconPath("dialog-information", "")
                    }
                    
                    source: resolvedIcon
                    visible: resolvedIcon !== ""
                }

                // Fallback text icon
                Text {
                    anchors.centerIn: parent
                    visible: appIcon.source === ""
                    text: root.notification.appName ? root.notification.appName.charAt(0).toUpperCase() : "N"
                    font.pixelSize: 14
                    font.bold: true
                    color: Theme.glass.textPrimary
                }
            }

            // App name
            Text {
                Layout.fillWidth: true
                text: root.notification.appName || "Notification"
                font.family: Theme.glass.fontFamily
                font.pixelSize: Theme.glass.fontSizeSmall
                font.bold: true
                color: Theme.glass.textSecondary
                elide: Text.ElideRight
            }

            // Time ago
            Text {
                text: root.notification.timeAgo || "now"
                font.family: Theme.glass.fontFamily
                font.pixelSize: Theme.glass.fontSizeSmall
                color: Theme.glass.textTertiary
            }

            // Close button
            GlassButton {
                implicitWidth: 24
                implicitHeight: 24
                icon: "󰅖"
                cornerRadius: 12
                onClicked: root.dismissed()
            }
        }

        // Summary
        Text {
            Layout.fillWidth: true
            visible: root.notification.summary && root.notification.summary !== ""
            text: root.notification.summary
            font.family: Theme.glass.fontFamily
            font.pixelSize: Theme.glass.fontSizeMedium
            font.bold: true
            color: Theme.glass.textPrimary
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }

        // Body
        Text {
            Layout.fillWidth: true
            visible: root.notification.body && root.notification.body !== ""
            text: root.notification.body.replace(/\n/g, "<br/>")
            font.family: Theme.glass.fontFamily
            font.pixelSize: Theme.glass.fontSizeSmall
            color: Theme.glass.textSecondary
            wrapMode: Text.Wrap
            elide: root.expanded ? Text.ElideNone : Text.ElideRight
            maximumLineCount: root.expanded ? 100 : 3
            textFormat: Text.RichText
            
            onLinkActivated: (link) => Qt.openUrlExternally(link)
        }

        // Expand/collapse button for long content
        GlassButton {
            Layout.alignment: Qt.AlignHCenter
            visible: root.notification.body && root.notification.body.length > 150
            implicitWidth: 100
            implicitHeight: 28
            text: root.expanded ? "Show less" : "Show more"
            cornerRadius: 14
            onClicked: root.expanded = !root.expanded
        }

        // Actions row
        RowLayout {
            Layout.fillWidth: true
            visible: root.notification.actions && root.notification.actions.length > 0
            spacing: 8

            Repeater {
                model: root.notification.actions

                GlassButton {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 32
                    text: modelData.text
                    cornerRadius: Theme.glass.cornerRadiusSmall
                    onClicked: root.actionInvoked(modelData.identifier)
                }
            }
        }

        // Bottom action bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Copy button
            GlassButton {
                id: copyButton
                Layout.fillWidth: true
                implicitHeight: 32
                icon: copied ? "󰄬" : "󰆏"
                text: copied ? "Copied" : "Copy"
                cornerRadius: Theme.glass.cornerRadiusSmall
                contentAlignment: Qt.AlignHCenter
                
                property bool copied: false

                onClicked: {
                    root.copyRequested(root.notification.body || root.notification.summary)
                    copied = true
                    copyResetTimer.restart()
                }

                Timer {
                    id: copyResetTimer
                    interval: 2000
                    onTriggered: copyButton.copied = false
                }
            }

            // Dismiss button
            GlassButton {
                Layout.fillWidth: true
                implicitHeight: 32
                icon: "󰅖"
                text: "Dismiss"
                cornerRadius: Theme.glass.cornerRadiusSmall
                contentAlignment: Qt.AlignHCenter
                onClicked: root.dismissed()
            }
        }
    }

    // Urgency indicator bar
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 3
        radius: 1.5
        color: root.urgencyColor
        visible: root.notification.urgency === 2
    }

    // Mouse handling for swipe
    MouseArea {
        anchors.fill: parent
        z: -1
        
        property real startX: 0
        property bool dragging: false

        onPressed: (mouse) => {
            startX = mouse.x
            dragging = true
        }

        onPositionChanged: (mouse) => {
            if (dragging) {
                root.dragX = mouse.x - startX
            }
        }

        onReleased: {
            dragging = false
            if (Math.abs(root.dragX) > root.dragThreshold) {
                root.dragX = root.dragX > 0 ? root.width + 50 : -root.width - 50
                dismissTimer.start()
            } else {
                root.dragX = 0
            }
        }

        Timer {
            id: dismissTimer
            interval: Theme.glass.animationDuration
            onTriggered: root.dismissed()
        }
    }
}
