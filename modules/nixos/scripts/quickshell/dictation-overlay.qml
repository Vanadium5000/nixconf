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
    
    // Poll status file
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            var file = readFile(root.statusFile);
            if (file) {
                try {
                    var data = JSON.parse(file);
                    root.isActive = data.active;
                    // Only update text if it's not empty, or handle accumulation?
                    // The daemon sends the *latest* segment. 
                    // If we want to show history, we need the daemon to send it.
                    // For now, let's just show what the daemon sends.
                    if (data.text) {
                         root.activeText = data.text;
                    }
                    root.statusError = data.error || "";
                } catch (e) {
                    console.log("JSON parse error: " + e);
                }
            } else {
                 root.isActive = false;
            }
        }
    }

    function readFile(path) {
        // QuickShell doesn't have a direct sync file read in JS context easily?
        // We can use `cat` process or similar, but polling process is heavy.
        // Actually, Quickshell might have `Io.File`? 
        // Let's use `cat` via Process for now as we did in lyrics, but polling is expensive.
        // Better: Use `FileWatch` or similar if available.
        // Looking at `lyrics-overlay.qml`, it spawns a process.
        // Let's spawn `cat` once per tick? That's bad.
        // Quickshell has `File` object?
        // Checking imports... `Quickshell.Io`.
        // Let's try `cat` for now, 100ms is 10 process/sec. A bit much.
        // 500ms?
    }
    
    Process {
        id: catProcess
        command: ["cat", root.statusFile]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (text) {
                     try {
                        var data = JSON.parse(text);
                        root.isActive = data.active;
                        root.activeText = data.text || root.activeText;
                        root.statusError = data.error || "";
                     } catch(e) {}
                }
            }
        }
    }
    
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: catProcess.running = true
    }
}
