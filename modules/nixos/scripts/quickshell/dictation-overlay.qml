import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "lib" as Lib

PanelWindow {
    id: root
    
    color: "transparent"
    
    // Position: Bottom of screen, centered
    anchors {
        bottom: true
        left: true
        right: true
    }
    
    margins {
        bottom: 80 // Above waybar
        left: (Screen.desktopAvailableWidth - 600) / 2
        right: (Screen.desktopAvailableWidth - 600) / 2
    }
    
    width: 600
    height: container.height + 40
    
    WlrLayershell.namespace: "dictation-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    
    // State parsing
    property string dictationStateFile: "/tmp/dictation-state.json"
    property string dictationText: "..."
    property string dictationMode: "idle"
    property real dictationVolume: 0.0
    property string dictationError: ""
    property string dictationProgress: ""
    
    Process {
        id: stateReader
        command: ["cat", root.dictationStateFile]
        running: false
        
        stdout: StdioCollector {
            onDataChanged: {
                try {
                    let st = JSON.parse(data);
                    root.dictationText = st.text || "...";
                    root.dictationMode = st.mode || "idle";
                    root.dictationVolume = st.volume || 0.0;
                    root.dictationError = st.error || "";
                    root.dictationProgress = st.progress || "";
                } catch(e) {
                    // Ignore parsing errors
                }
            }
        }
    }
    
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            stateReader.running = true;
        }
    }

    // Logic for control actions
    function sendCommand(cmd) {
        commandRunner.command = ["dictation", "cmd", cmd];
        commandRunner.running = true;
    }

    Process { id: commandRunner; running: false }
    Process { id: copier; running: false }

    Item {
        id: container
        anchors.centerIn: parent
        width: parent.width - 40
        height: Math.min(contentLayout.implicitHeight + 160, 400)

        Lib.GlassPanel {
            anchors.fill: parent
            cornerRadius: 26
        }

        ColumnLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // --- Header: Status & Close ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: {
                        if (root.dictationMode === "error") return "#fc5454"; // Lib.Theme.error
                        if (root.dictationMode === "live") return "#54fc54"; // Lib.Theme.success
                        if (root.dictationMode === "transcribe") return "#5454fc"; // Lib.Theme.accent
                        if (root.dictationMode === "downloading") return "#54fcfc"; // Lib.Theme.accentAlt
                        return "#d0d0d0"; // Lib.Theme.foregroundAlt
                    }
                    
                    // Pulse animation
                    opacity: 1.0
                    SequentialAnimation on opacity {
                        running: root.dictationMode === "live"
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 0.4; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                    }
                }

                Text {
                    text: root.dictationMode.toUpperCase()
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    color: "#d0d0d0"
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Lib.GlassButton {
                    Layout.preferredWidth: 32; Layout.preferredHeight: 32
                    text: "×"
                    cornerRadius: 16
                    onClicked: root.sendCommand("hide")
                }
            }

            // --- Content: The Transcript Notepad ---
            ScrollView {
                id: transcriptScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                
                TextArea {
                    id: notepad
                    width: transcriptScroll.width - 16
                    text: root.dictationMode === "error" ? root.dictationError : root.dictationText
                    color: root.dictationMode === "error" ? "#fc5454" : "#e0e0e0"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                    wrapMode: Text.Wrap
                    background: null
                    padding: 8
                    selectByMouse: true
                    
                    // Auto-scroll to bottom only if we're near the bottom
                    onTextChanged: {
                        if (transcriptScroll.contentItem.contentY >= contentHeight - transcriptScroll.height - 100) {
                            Qt.callLater(() => {
                                transcriptScroll.contentItem.contentY = Math.max(0, contentHeight - transcriptScroll.height)
                            })
                        }
                    }
                }
            }

            // --- Footer: Controls ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Lib.GlassButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    text: "Copy"
                    onClicked: {
                        copier.command = ["wl-copy", "--type", "text/plain", notepad.text];
                        copier.running = true;
                    }
                }

                Lib.GlassButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    text: "Clear"
                    onClicked: root.sendCommand("clear")
                }

                Lib.GlassButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    text: root.dictationMode === "live" ? "Pause" : "Resume"
                    onClicked: root.sendCommand("pause")
                }
            }
        }
    }
}
