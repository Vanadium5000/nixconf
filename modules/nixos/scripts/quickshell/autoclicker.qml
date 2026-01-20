import Quickshell
import Quickshell.Wayland
import QtQuick 2.15
import "./lib" 1.0

PanelWindow {
    id: root
    WlrLayershell.layer: WlrLayer.Overlay

    // Read margins as environment variable strings
    property int marginLeft: parseInt(Quickshell.env("X") ?? "0")
    property int marginTop: parseInt(Quickshell.env("Y") ?? "0")
    property string inputColor: Quickshell.env("COLOR") ?? Theme.error // Default to Red

    implicitWidth: 32
    implicitHeight: 32
    color: "transparent"
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.top: true

    mask: Region {}

    // x, y position (centered)
    margins.left: marginLeft - implicitWidth / 2
    margins.top: marginTop - implicitHeight / 2

    // Autoclicker Indicator
    Item {
        anchors.fill: parent

        // Outer Ring
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
