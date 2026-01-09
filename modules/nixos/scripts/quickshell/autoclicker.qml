import Quickshell
import Quickshell.Wayland
import QtQuick 2.15

PanelWindow {
    id: root
    WlrLayershell.layer: WlrLayer.Overlay

    // Read margins as environment variable strings
    property int marginLeft: parseInt(Quickshell.env("X") ?? "0")
    property int marginTop: parseInt(Quickshell.env("Y") ?? "0")
    property string inputColor: Quickshell.env("COLOR") ?? "#ff0000" // Default to Red for autoclicker

    implicitWidth: 24
    implicitHeight: 24
    color: "transparent"
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.top: true

    mask: Region {}  // Empty = ignore all mouse input

    // x, y position (centered)
    margins.left: marginLeft - implicitWidth / 2
    margins.top: marginTop - implicitHeight / 2

    // Autoclicker Indicator (Target Circle)
    Item {
        anchors.fill: parent

        // Outer Ring Shadow
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: "black"
            opacity: 0.5
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
}
