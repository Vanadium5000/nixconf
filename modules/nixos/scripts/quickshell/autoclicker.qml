/*
 * autoclicker.qml - Visual Indicator for Autoclicker
 * 
 * Displays a pulsing ring overlay at the specified coordinates to indicate
 * active autoclicking behavior. Used in conjunction with a backend script.
 *
 * Environment Variables:
 *   X, Y  - Screen coordinates for the indicator center
 *   COLOR - Hex color for the indicator ring (default: Theme.error/Red)
 */

import Quickshell
import Quickshell.Wayland
import QtQuick
import "./lib"

PanelWindow {
    id: root
    
    // --- Window Configuration ---
    // Overlay layer ensures it sits above most application windows
    WlrLayershell.layer: WlrLayer.Overlay

    // Read margins as environment variable strings
    property int marginLeft: parseInt(Quickshell.env("X") ?? "0")
    property int marginTop: parseInt(Quickshell.env("Y") ?? "0")
    property string inputColor: Quickshell.env("COLOR") ?? Theme.error // Default to Red

    // Small fixed size for the indicator
    implicitWidth: 32
    implicitHeight: 32
    color: "transparent"
    
    // Passthrough input to windows below
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.top: true

    // Click-through mask
    mask: Region {}

    // Positioning
    margins.left: root.marginLeft - implicitWidth / 2
    margins.top: root.marginTop - implicitHeight / 2

    // --- Visuals ---
    Item {
        anchors.fill: parent

        // Outer Ring (Static)
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: root.inputColor
            opacity: 0.8

            // Glassy fill
            color: Theme.rgba(root.inputColor, 0.1)
        }

        // Inner Dot
        Rectangle {
            width: 6
            height: 6
            radius: 3
            color: root.inputColor
            anchors.centerIn: parent

            layer.enabled: true
            layer.effect: RectangularShadow {
                radius: 4
                color: root.inputColor
            }
        }

        // Pulsing Animation
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            PropertyAnimation {
                to: 1.0
                duration: 800
                easing.type: Easing.InOutQuad
            }
            PropertyAnimation {
                to: 0.4
                duration: 800
                easing.type: Easing.InOutQuad
            }
        }

        // Rotation Animation for "Active" feel
        RotationAnimation on rotation {
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 2000
        }
    }

    // Main Ring
    Rectangle {
        anchors.centerIn: parent
        width: parent.width - 2
        height: parent.height - 2
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: root.inputColor
        opacity: 0.8
    }

    // Inner Dot Shadow
    Rectangle {
        width: 6
        height: 6
        radius: 3
        color: "black"
        anchors.centerIn: parent
        opacity: 0.5
    }

    // Inner Dot
    Rectangle {
        width: 4
        height: 4
        radius: 2
        color: root.inputColor
        anchors.centerIn: parent
        opacity: 1.0
    }

    // Pulsing Animation (Optional but nice)
    SequentialAnimation on opacity {
        loops: Animation.Infinite
        PropertyAnimation {
            to: 1.0
            duration: 1000
        }
        PropertyAnimation {
            to: 0.6
            duration: 1000
        }
    }
}
