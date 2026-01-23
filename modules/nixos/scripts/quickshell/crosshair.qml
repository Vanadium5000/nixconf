/*
 * crosshair.qml - Gaming Crosshair Overlay
 *
 * Renders a customizable crosshair overlay on the screen.
 * Useful for games that don't provide a native crosshair.
 *
 * Features:
 * - Single instance locking (toggleable)
 * - Neon glow effect
 * - Customizable color via environment variable
 */

import Quickshell
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects
import "./lib"

PanelWindow {
    id: root
    
    // Ensure only one crosshair exists
    InstanceLock {
        lockName: "crosshair"
        toggle: true
    }
    
    WlrLayershell.layer: WlrLayer.Overlay

    // --- Configuration ---
    property int marginLeft: parseInt(Quickshell.env("X") ?? "0")
    property int marginTop: parseInt(Quickshell.env("Y") ?? "0")
    property string inputColor: Quickshell.env("COLOR") ?? Theme.success // Default to Success Green

    implicitWidth: 30
    implicitHeight: 30
    color: "transparent"
    
    // Input transparency
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.top: true

    mask: Region {}

    // Positioning
    margins.left: root.marginLeft - implicitWidth / 2
    margins.top: root.marginTop - implicitHeight / 2

    // --- Visuals ---
    Item {
        anchors.centerIn: parent
        width: 30
        height: 30

        // Vertical Line (Shadow/Outline)
        Rectangle {
            width: 3
            height: 30
            color: Theme.background
            anchors.centerIn: parent
            opacity: 0.8
        }

        // Horizontal Line (Shadow)
        Rectangle {
            width: 30
            height: 3
            color: Theme.background
            anchors.centerIn: parent
            opacity: 0.8
        }

        // Vertical Line (Color)
        Rectangle {
            width: 1
            height: 28
            color: root.inputColor
            anchors.centerIn: parent
            opacity: 1.0

            // Neon Glow
            layer.enabled: true
            layer.effect: Glow {
                radius: 4
                samples: 9
                color: root.inputColor
                spread: 0.5
            }
        }

        // Horizontal Line (Color)
        Rectangle {
            width: 28
            height: 1
            color: root.inputColor
            anchors.centerIn: parent
            opacity: 1.0

            // Neon Glow
            layer.enabled: true
            layer.effect: Glow {
                radius: 4
                samples: 9
                color: root.inputColor
                spread: 0.5
            }
        }

        // Center Dot
        Rectangle {
            width: 1
            height: 1
            color: Theme.background
            anchors.centerIn: parent
            opacity: 0.5
        }
    }
}
