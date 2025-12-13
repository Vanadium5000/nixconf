import Quickshell
import Quickshell.Wayland
import QtQuick 2.15

PanelWindow {
    WlrLayershell.layer: WlrLayer.Overlay

    // Read margins as environment variable strings
    property int marginLeft: parseInt(Quickshell.env("X") ?? "0")
    property int marginTop: parseInt(Quickshell.env("Y") ?? "0")

    implicitWidth: 20
    implicitHeight: 20
    color: "transparent"
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.top: true

    // x, y position
    margins.left: marginLeft - 20 / 2
    margins.top: marginTop - 20 / 2

    // Horizontal line
    Rectangle {
        implicitWidth: 20     // shorter line for precise crosshair
        implicitHeight: 1      // thinner
        color: "#FF0000"   // red with slight transparency
        opacity: 0.7
        anchors.centerIn: parent
    }

    // Vertical line
    Rectangle {
        implicitWidth: 1       // thinner
        implicitHeight: 20     // shorter
        color: "#FF0000"   // same color
        opacity: 0.7
        anchors.centerIn: parent
    }
}
