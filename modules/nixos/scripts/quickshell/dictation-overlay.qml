import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "lib" as Lib

PanelWindow {
    id: root
    
    color: "transparent"
    
    // Position
    anchors {
        bottom: true
        left: true
        right: true
    }
    
    margins {
        bottom: 80 // Above waybar
        left: 20
        right: 20
    }
    
    width: Screen.desktopAvailableWidth - 40
    height: container.implicitHeight + 32
    
    WlrLayershell.namespace: "dictation-overlay"
    WlrLayershell.layer: WlrLayer.Top
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
                    // Ignore parsing errors (file might be mid-write)
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
    
    Item {
        id: container
        anchors.centerIn: parent
        width: Math.min(contentLayout.implicitWidth + 64, root.width - 40)
        height: contentLayout.implicitHeight + 32
        
        Lib.GlassPanel {
            anchors.fill: parent
            
            // Allow clicking through the panel background
            mask: Region {
                item: contentLayout
            }
            
            RowLayout {
                id: contentLayout
                anchors.centerIn: parent
                spacing: 16
                
                // Volume/Status Indicator
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 12
                    height: 12
                    radius: 6
                    
                    color: {
                        if (root.dictationMode === "error") return Lib.Theme.error;
                        if (root.dictationMode === "live") return Lib.Theme.success;
                        if (root.dictationMode === "transcribe") return Lib.Theme.accent;
                        if (root.dictationMode === "downloading") return Lib.Theme.accentAlt;
                        return Lib.Theme.foregroundAlt;
                    }
                    
                    // Pulse effect for live mode based on volume
                    opacity: root.dictationMode === "live" ? 0.4 + (root.dictationVolume * 0.6) : 1.0
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                    }
                }
                
                // Main Text
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.maximumWidth: root.width - 120 // Leave room for margins and indicator
                    
                    text: {
                        if (root.dictationMode === "error") return root.dictationError || "Error";
                        if (root.dictationMode === "downloading") return root.dictationText + " " + root.dictationProgress;
                        if (root.dictationMode === "transcribe") return root.dictationText + " " + root.dictationProgress;
                        return root.dictationText;
                    }
                    
                    color: root.dictationMode === "error" ? Lib.Theme.error : Lib.Theme.foreground
                    font.family: Lib.Theme.fontName
                    font.pixelSize: Lib.Theme.fontSizeLarge
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
