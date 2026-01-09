import Quickshell
import Quickshell.Wayland
import QtQuick 2.15

PanelWindow {
    id: root
    WlrLayershell.layer: WlrLayer.Overlay

    // Read margins as environment variable strings
    property int marginLeft: parseInt(Quickshell.env("X") ?? "0")
    property int marginTop: parseInt(Quickshell.env("Y") ?? "0")
    property string inputColor: Quickshell.env("COLOR") ?? "#00ff00" // Default to Green for crosshair

    implicitWidth: 30
    implicitHeight: 30
    color: "transparent"
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.top: true

    mask: Region {}  // Empty = ignore all mouse input

    // x, y position (centered)
    margins.left: marginLeft - implicitWidth / 2
    margins.top: marginTop - implicitHeight / 2

    // Crosshair Container
    Item {
        anchors.centerIn: parent
        width: 30
        height: 30

        // Vertical Line (Black Border)
        Rectangle {
            width: 3
            height: 30
            color: "black"
            anchors.centerIn: parent
            opacity: 0.8
        }
        
        // Horizontal Line (Black Border)
        Rectangle {
            width: 30
            height: 3
            color: "black"
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
        }

        // Horizontal Line (Color)
        Rectangle {
            width: 28
            height: 1
            color: root.inputColor
            anchors.centerIn: parent
            opacity: 1.0
        }
        
        // Center Dot (Optional, helpful for precision)
        Rectangle {
            width: 1
            height: 1
            color: "black" 
            anchors.centerIn: parent
            opacity: 0.5
        }
    }
}
