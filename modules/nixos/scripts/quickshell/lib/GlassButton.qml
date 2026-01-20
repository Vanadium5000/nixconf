import QtQuick
import QtQuick.Layouts
import "."

Item {
    id: root

    property string text: ""
    property string icon: ""
    property bool active: false
    signal clicked()

    implicitWidth: 120
    implicitHeight: 40

    // Hover state
    property bool hovered: hoverHandler.hovered
    property bool pressed: tapHandler.pressed

    Rectangle {
        id: background
        anchors.fill: parent
        radius: Theme.rounding

        // Dynamic background color based on state
        color: {
            if (root.active) {
                return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
            }
            if (root.pressed) {
                return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
            }
            if (root.hovered) {
                return Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.12)
            }
            return Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.35)
        }

        // Dynamic border
        border.color: {
            if (root.active) {
                return Theme.accent
            }
            if (root.hovered) {
                return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
            }
            return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.borderOpacity)
        }
        border.width: 1

        // Animations
        Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
        Behavior on border.color { ColorAnimation { duration: Theme.animationDuration } }

        // Specular highlight for glass effect
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.45
            radius: Theme.rounding
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
                font.family: Theme.fontName
                font.pixelSize: Theme.fontSizeLarge
                color: root.active ? Theme.accentAlt : Theme.foreground
            }

            // Label
            Text {
                text: root.text
                font.family: Theme.fontName
                font.pixelSize: Theme.fontSize
                color: root.active ? Theme.accentAlt : Theme.foreground
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
