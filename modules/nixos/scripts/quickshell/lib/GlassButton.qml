import QtQuick
import QtQuick.Layouts
import "."

Item {
    id: root

    property string text: ""
    property string icon: ""
    property bool active: false
    property int cornerRadius: Theme.glass.cornerRadiusSmall
    signal clicked()

    implicitWidth: 120
    implicitHeight: 40

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

        RowLayout {
            anchors.centerIn: parent
            spacing: 8

            // Icon (if present)
            Text {
                visible: root.icon !== ""
                text: root.icon
                font.family: Theme.glass.fontFamily
                font.pixelSize: Theme.glass.fontSizeLarge
                color: root.active ? Theme.glass.accentColorAlt : Theme.glass.textPrimary
            }

            // Label
            Text {
                visible: root.text !== "" && root.icon !== root.text // Don't duplicate if text is used as icon
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
        onTapped: root.clicked()
    }
}
