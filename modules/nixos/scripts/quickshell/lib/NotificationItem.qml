/*
 * NotificationItem.qml - Individual notification display component
 *
 * Displays a single notification with:
 * - App icon and name
 * - Summary and body text
 * - Timestamp
 * - Action buttons
 * - Copy button
 * - Swipe to dismiss
 * - Expandable body for long content
 */

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import Qt5Compat.GraphicalEffects
import "."

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
        switch (notification.urgency) {
            case NotificationUrgency.Critical: return Theme.colors.red
            case NotificationUrgency.Low: return Theme.colors.base04
            default: return Theme.glass.accentColor
        }
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
                        if (!notification.appIcon || notification.appIcon === "") {
                            return Quickshell.iconPath("dialog-information", "")
                        }
                        if (notification.appIcon.startsWith("/")) {
                            return "file://" + notification.appIcon
                        }
                        var resolved = Quickshell.iconPath(notification.appIcon, "")
                        return resolved !== "" ? resolved : Quickshell.iconPath("dialog-information", "")
                    }
                    
                    source: resolvedIcon
                    visible: resolvedIcon !== ""
                }

                // Fallback text icon
                Text {
                    anchors.centerIn: parent
                    visible: appIcon.source === ""
                    text: notification.appName.charAt(0).toUpperCase()
                    font.pixelSize: 14
                    font.bold: true
                    color: Theme.glass.textPrimary
                }
            }

            // App name
            Text {
                Layout.fillWidth: true
                text: notification.appName || "Notification"
                font.family: Theme.glass.fontFamily
                font.pixelSize: Theme.glass.fontSizeSmall
                font.bold: true
                color: Theme.glass.textSecondary
                elide: Text.ElideRight
            }

            // Time ago
            Text {
                text: notification.timeAgo
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

        // Notification image (if present)
        Image {
            id: notifImage
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 120 : 0
            visible: notification.image && notification.image !== ""
            source: notification.image ? (notification.image.startsWith("/") ? "file://" + notification.image : notification.image) : ""
            fillMode: Image.PreserveAspectCrop
            
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: notifImage.width
                    height: notifImage.height
                    radius: Theme.glass.cornerRadiusSmall
                }
            }
        }

        // Summary
        Text {
            Layout.fillWidth: true
            visible: notification.summary && notification.summary !== ""
            text: notification.summary
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
            visible: notification.body && notification.body !== ""
            text: notification.body.replace(/\n/g, "<br/>")
            font.family: Theme.glass.fontFamily
            font.pixelSize: Theme.glass.fontSizeSmall
            color: Theme.glass.textSecondary
            wrapMode: Text.Wrap
            elide: root.expanded ? Text.ElideNone : Text.ElideRight
            maximumLineCount: root.expanded ? 100 : 3
            textFormat: Text.RichText
            
            onLinkActivated: (link) => Qt.openUrlExternally(link)

            MouseArea {
                anchors.fill: parent
                cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                acceptedButtons: Qt.NoButton
            }
        }

        // Expand/collapse button for long content
        GlassButton {
            Layout.alignment: Qt.AlignHCenter
            visible: notification.body && notification.body.length > 150
            implicitWidth: 100
            implicitHeight: 28
            text: root.expanded ? "Show less" : "Show more"
            cornerRadius: 14
            onClicked: root.expanded = !root.expanded
        }

        // Actions row
        RowLayout {
            Layout.fillWidth: true
            visible: notification.actions && notification.actions.length > 0
            spacing: 8

            Repeater {
                model: notification.actions

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
                icon: copyIcon.copied ? "󰄬" : "󰆏"
                text: copyIcon.copied ? "Copied" : "Copy"
                cornerRadius: Theme.glass.cornerRadiusSmall
                contentAlignment: Qt.AlignHCenter
                
                property bool copied: false

                onClicked: {
                    root.copyRequested(notification.body || notification.summary)
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
        visible: notification.urgency === NotificationUrgency.Critical
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
                // Animate off screen then dismiss
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
