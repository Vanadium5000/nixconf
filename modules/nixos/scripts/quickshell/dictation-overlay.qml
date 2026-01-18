pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick 2.15
import QtQuick.Layouts 1.15

PanelWindow {
    id: root
    WlrLayershell.layer: WlrLayer.Overlay
    
    // Config
    property string statusFile: "/tmp/dictation_status.json"
    property string activeText: ""
    property bool isActive: false
    property string statusError: ""

    // Sizing
    implicitWidth: screen ? screen.width : 1920
    implicitHeight: 200
    color: "transparent"
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore

    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    margins.bottom: 100

    mask: Region {}

    // Background
    Rectangle {
        anchors.fill: parent
        color: "#80000000"
        radius: 10
        visible: root.isActive
        
        border.width: 2
        border.color: root.isActive ? "#ff0000" : "transparent"
        
        // Pulsate border when active
        SequentialAnimation on border.color {
            loops: Animation.Infinite
            running: root.isActive
            ColorAnimation { from: "#ff0000"; to: "#800000"; duration: 800 }
            ColorAnimation { from: "#800000"; to: "#ff0000"; duration: 800 }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.8
        spacing: 10

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.isActive ? "🎙️ Listening..." : "Idle"
            color: "#ff0000"
            font.pixelSize: 24
            font.bold: true
            visible: root.isActive
        }

        Text {
            id: contentText
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.activeText
            color: "#ffffff"
            font.pixelSize: 32
            font.bold: true
            wrapMode: Text.WordWrap
            visible: root.isActive
        }
        
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.statusError
            color: "#ff5555"
            font.pixelSize: 18
            visible: root.statusError !== ""
        }
    }
    
    // Poll status using the dictation daemon
    Timer {
        id: pollTimer
        interval: 50 // Fast polling for responsiveness
        running: true
        repeat: true
        onTriggered: {
            if (!statusProcess.running) {
                statusProcess.running = true;
            }
        }
    }

    Process {
        id: statusProcess
        command: ["dictation", "status"]
        running: false
        
        stdout: StdioCollector {
            onStreamFinished: {
                if (text) {
                     try {
                        var data = JSON.parse(text);
                        // Atomic update from daemon
                        root.isActive = data.active;
                        if (data.text) root.activeText = data.text;
                        root.statusError = data.error || "";
                     } catch(e) {}
                }
            }
        }
    }
}
