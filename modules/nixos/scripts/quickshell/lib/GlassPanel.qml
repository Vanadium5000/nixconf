import QtQuick
import Qt5Compat.GraphicalEffects
import "."

Item {
    id: root

    default property alias content: container.children
    property bool hasShadow: true
    property bool hasBlur: true
    property bool hasBorder: true

    // Customization
    property real opacityValue: Theme.glassOpacity
    property int cornerRadius: Theme.rounding

    // --- Drop Shadow (rendered first, behind everything) ---
    DropShadow {
        anchors.fill: backgroundRect
        source: backgroundRect
        z: -1
        horizontalOffset: 0
        verticalOffset: 4
        radius: Theme.shadowRadius
        samples: 25
        color: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
        visible: root.hasShadow
        cached: true
    }

    // The main visual container
    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        radius: root.cornerRadius
        color: Qt.rgba(
            Theme.background.r,
            Theme.background.g,
            Theme.background.b,
            root.opacityValue
        )
        clip: true

        // --- Specular Highlight (Top Reflection) ---
        Rectangle {
            id: highlight
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.5
            radius: root.cornerRadius

            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Theme.highlightOpacity) }
                GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.02) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // --- Inner Stroke (Cut Glass Effect - top edge highlight) ---
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: "transparent"
            border.color: Theme.innerStrokeColor
            border.width: Theme.innerStroke
        }

        // --- Outer Border ---
        border.color: root.hasBorder ? Qt.rgba(
            Theme.accent.r,
            Theme.accent.g,
            Theme.accent.b,
            Theme.borderOpacity
        ) : "transparent"
        border.width: root.hasBorder ? Theme.borderWidth : 0
    }

    // Content Container
    Item {
        id: container
        anchors.fill: parent
        anchors.margins: Theme.gapsIn
        z: 10
    }
}
