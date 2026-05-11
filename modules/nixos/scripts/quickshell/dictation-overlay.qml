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
    implicitWidth: 360
    implicitHeight: 132

    anchors {
        bottom: true
        left: true
    }
    margins.bottom: 92
    margins.left: Math.round((Screen.width - implicitWidth) / 2)

    WlrLayershell.namespace: "dictation-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    property string dictationText: "Listening..."
    property string dictationMode: "idle"
    property real dictationVolume: 0.0
    property string dictationError: ""
    property bool active: dictationMode === "recording"
    property int animationTick: 0

    Process {
        id: stateReader
        command: ["dictation", "status"]
        running: false
        stdout: StdioCollector {
            id: stdoutCollector
            onStreamFinished: {
                try {
                    const st = JSON.parse(stdoutCollector.text.trim())
                    root.dictationText = st.error || st.text || "Listening..."
                    root.dictationMode = st.mode || "idle"
                    root.dictationVolume = st.volume || 0.0
                    root.dictationError = st.error || ""
                } catch(e) {}
            }
        }
    }

    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            root.animationTick += 1
            stateReader.running = true
        }
    }

    function sendCommand(cmd) {
        if (commandRunner.running) return
        commandRunner.command = ["dictation", cmd]
        commandRunner.running = true
    }

    Process { id: commandRunner; running: false }

    Item {
        anchors.fill: parent

        Lib.GlassPanel {
            anchors.fill: parent
            cornerRadius: 28
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 16

            Item {
                Layout.preferredWidth: 74
                Layout.preferredHeight: 74

                Repeater {
                    model: 18
                    Rectangle {
                        required property int index
                        width: 4
                        radius: 2
                        color: root.dictationMode === "error" ? "#fc5454" : "#8bd5ff"
                        opacity: 0.38 + Math.min(0.62, root.dictationVolume + index / 32)
                        height: 10 + Math.max(2, root.dictationVolume * 44 * Math.abs(Math.sin(index * 0.73 + root.animationTick / 2)))
                        x: 6 + index * 3.6
                        y: 37 - height / 2

                        Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 90 } }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 52; height: 52; radius: 26
                    color: "transparent"
                    border.width: 2
                    border.color: root.active ? "#8bd5ff" : root.dictationMode === "error" ? "#fc5454" : "#cdd6f4"
                    opacity: 0.7
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: root.dictationMode === "recording" ? "Dictation is listening" : root.dictationMode === "transcribing" ? "Turning audio into text" : root.dictationMode === "error" ? "Dictation failed" : "Dictation"
                    color: "#f5f7ff"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.dictationMode === "recording" ? "Toggle again to finish · Esc/cancel to discard" : root.dictationText
                    color: root.dictationMode === "error" ? "#fc5454" : "#b8c0d6"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            ColumnLayout {
                spacing: 8

                Lib.GlassButton {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    text: "✓"
                    visible: root.dictationMode === "recording"
                    cornerRadius: 17
                    onClicked: root.sendCommand("finish")
                }

                Lib.GlassButton {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    text: "×"
                    cornerRadius: 17
                    onClicked: root.sendCommand("cancel")
                }
            }
        }
    }
}
