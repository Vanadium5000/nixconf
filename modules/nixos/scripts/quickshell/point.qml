import Quickshell
import Quickshell.Wayland
import QtQuick 2.15

PanelWindow {
    id: root
    WlrLayershell.layer: WlrLayer.Overlay

    // Read margins as environment variable strings
    property int marginLeft: parseInt(Quickshell.env("X") ?? "0")
    property int marginTop: parseInt(Quickshell.env("Y") ?? "0")
    property string inputColor: Quickshell.env("COLOR") ?? "#ffffff"

    implicitWidth: 20
    implicitHeight: 20
    color: "transparent"
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.top: true

    mask: Region {}  // Empty = ignore all mouse input

    // x, y position
    margins.left: marginLeft - 20 / 2
    margins.top: marginTop - 20 / 2

    // Horizontal line
    Rectangle {
        implicitWidth: 20     // shorter line for precise crosshair
        implicitHeight: 1      // thinner
        color: root.inputColor
        opacity: 0.6
        anchors.centerIn: parent
    }

    // Vertical line
    Rectangle {
        implicitWidth: 1       // thinner
        implicitHeight: 20     // shorter
        color: root.inputColor
        opacity: 0.6
        anchors.centerIn: parent
    }
}
