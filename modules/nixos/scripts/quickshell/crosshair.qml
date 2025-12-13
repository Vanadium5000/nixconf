import Quickshell
import QtQuick 2.15

PanelWindow {
    width: 50
    height: 50
    color: "transparent"

    // Horizontal line
    Rectangle {
        width: 20      // shorter line for precise crosshair
        height: 1      // thinner
        color: "#FF5555AA"   // red with slight transparency
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }

    // Vertical line
    Rectangle {
        width: 1       // thinner
        height: 20     // shorter
        color: "#FF5555AA"   // same color
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }

    Component.onCompleted: {
        window.setFlags(Qt.FramelessWindowHint)
        window.setOpacity(1.0)
    }
}

