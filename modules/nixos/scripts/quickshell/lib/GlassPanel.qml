/*
 * GlassPanel.qml - Base Glass Surface Component
 *
 * The fundamental building block of the Liquid Glass UI.
 * Renders a frosted glass panel with:
 * - Backdrop blur and transparency
 * - Specular highlight gradient (top edge)
 * - "Cut glass" inner stroke effect
 * - Drop shadow (optional)
 * - Configurable border and corner radius
 */

import QtQuick
import Qt5Compat.GraphicalEffects
import "."

Item {
    id: root

    default property alias content: container.data
    property bool hasShadow: true
    property bool hasBlur: true
    property bool hasBorder: true

    // Customization
    property color color: Theme.glass.backgroundColor
    property real opacityValue: 1.0 // Color already handles alpha, but this can override
    property int cornerRadius: Theme.glass.cornerRadius

    // --- Drop Shadow (rendered first, behind everything) ---
    DropShadow {
        anchors.fill: backgroundRect
        source: backgroundRect
        z: -1
        horizontalOffset: 0
        verticalOffset: Theme.glass.shadowOffsetY
        radius: Theme.glass.shadowRadius
        samples: 25
        color: Qt.rgba(0, 0, 0, Theme.glass.shadowOpacity)
        visible: root.hasShadow
        cached: true
    }

    // The main visual container
    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.color // Use the provided color directly
        clip: true

        // --- Specular Highlight (Top Reflection) ---
        Rectangle {
            id: highlight
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.4
            radius: root.cornerRadius

            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(1, 1, 1, Theme.glass.highlightOpacity)
                }
                GradientStop {
                    position: 0.35
                    color: Qt.rgba(1, 1, 1, Theme.glass.highlightOpacity * 0.3)
                }
                GradientStop {
                    position: 1.0
                    color: "transparent"
                }
            }
        }

        // --- Inner Stroke (Cut Glass Effect - top edge highlight) ---
        Rectangle {
            anchors.fill: parent
            anchors.margins: Theme.glass.borderWidth
            radius: root.cornerRadius - Theme.glass.borderWidth
            color: "transparent"
            border.color: Theme.glass.innerStrokeColor
            border.width: 1
        }

        // --- Outer Border ---
        border.color: root.hasBorder ? Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, Theme.glass.borderOpacity) : "transparent"
        border.width: root.hasBorder ? Theme.glass.borderWidth : 0
    }

    // Content Container
    Item {
        id: container
        anchors.fill: parent
        anchors.margins: Theme.glass.padding
        z: 10
    }
}
