/*
 * GlassButton.qml - Interactive Glass Button Component
 *
 * A reusable button component implementing the Liquid Glass design language.
 * Supports:
 * - Text, Icon (name or source), or Emoji content
 * - Hover, pressed, and active states with smooth transitions
 * - Right-click signal support
 * - Dynamic coloring based on Theme tokens
 */

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "."

Item {
    id: root

    property string text: ""
    property string icon: "" // Emoji/Text icon (legacy support)
    property string iconSource: "" // Icon name (e.g. "firefox") or path
    property bool active: false
    property int cornerRadius: Theme.glass.cornerRadiusSmall
    signal clicked()
    signal rightClicked() // Add right click signal

    implicitWidth: 48
    implicitHeight: 48

    // Hover state
    property bool hovered: hoverHandler.hovered
    property bool pressed: tapHandler.pressed

    Rectangle {
        id: background
        anchors.fill: parent
        radius: root.cornerRadius

        // Dynamic background color based on state
        color: {
            if (root.active) {
                return Qt.rgba(
                    Theme.glass.accentColor.r,
                    Theme.glass.accentColor.g,
                    Theme.glass.accentColor.b,
                    0.35
                )
            }
            if (root.pressed) {
                return Qt.rgba(
                    Theme.glass.accentColor.r,
                    Theme.glass.accentColor.g,
                    Theme.glass.accentColor.b,
                    0.25
                )
            }
            if (root.hovered) {
                return Qt.rgba(1, 1, 1, 0.12)
            }
            return Qt.rgba(1, 1, 1, 0.05)
        }

        // Dynamic border
        border.color: {
            if (root.active) {
                return Theme.glass.accentColor
            }
            if (root.hovered) {
                return Qt.rgba(
                    Theme.glass.accentColor.r,
                    Theme.glass.accentColor.g,
                    Theme.glass.accentColor.b,
                    0.5
                )
            }
            return Qt.rgba(
                Theme.glass.accentColor.r,
                Theme.glass.accentColor.g,
                Theme.glass.accentColor.b,
                Theme.glass.borderOpacity
            )
        }
        border.width: 1

        // Animations
        Behavior on color { ColorAnimation { duration: Theme.glass.animationDuration } }
        Behavior on border.color { ColorAnimation { duration: Theme.glass.animationDuration } }

        // Specular highlight for glass effect
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.45
            radius: root.cornerRadius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.08) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Content
        Item {
            anchors.fill: parent
            anchors.margins: 4

            // 1. IconImage (Preferred) - Use Quickshell.iconPath() for proper XDG theme lookup
            IconImage {
                id: mainIcon
                anchors.centerIn: parent
                implicitSize: Math.min(parent.width, parent.height) - 8
                
                // Use Quickshell.iconPath with fallback for proper icon theme resolution
                source: root.iconSource !== "" 
                    ? Quickshell.iconPath(root.iconSource, "application-x-executable")
                    : Quickshell.iconPath("application-x-executable")
                
                visible: root.iconSource !== "" || (root.icon === "" && root.text === "")
            }

            // 2. Text/Emoji Icon (Fallback)
            Text {
                anchors.centerIn: parent
                visible: root.iconSource === "" && root.icon !== ""
                text: root.icon
                font.family: Theme.glass.fontFamily
                font.pixelSize: 24
                color: root.active ? Theme.glass.accentColorAlt : Theme.glass.textPrimary
            }

            // 3. Text Label (Only if no icon at all, or strictly text button)
            Text {
                anchors.centerIn: parent
                visible: root.iconSource === "" && root.icon === "" && root.text !== ""
                text: root.text
                font.family: Theme.glass.fontFamily
                font.pixelSize: Theme.glass.fontSizeMedium
                color: root.active ? Theme.glass.accentColorAlt : Theme.glass.textPrimary
                font.bold: root.active
            }
        }
    }

    HoverHandler {
        id: hoverHandler
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (eventPoint, button) => {
            if (button === Qt.RightButton) {
                root.rightClicked()
            } else {
                root.clicked()
            }
        }
    }
}
