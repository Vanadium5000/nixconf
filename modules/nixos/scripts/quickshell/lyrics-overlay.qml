pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick 2.15
import QtQuick.Layouts 1.15

PanelWindow {
    id: root
    WlrLayershell.layer: WlrLayer.Overlay

    // Configuration via environment variables
    property int numLines: parseInt(Quickshell.env("LYRICS_LINES") ?? "3")
    property string positionMode: Quickshell.env("LYRICS_POSITION") ?? "bottom"
    property int fontSize: parseInt(Quickshell.env("LYRICS_FONT_SIZE") ?? "28")
    property string textColor: Quickshell.env("LYRICS_COLOR") ?? "#ffffff"
    property real textOpacity: parseFloat(Quickshell.env("LYRICS_OPACITY") ?? "0.95")
    property string fontFamily: Quickshell.env("LYRICS_FONT") ?? "sans-serif"

    // Lyrics data
    property string currentLine: ""
    property var upcomingLines: []
    property string trackInfo: ""
    property bool isPlaying: false

    // Window sizing
    implicitWidth: screen ? screen.width : 1920
    implicitHeight: contentColumn.implicitHeight + 60
    color: "transparent"
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore

    // Positioning - use anchors based on position mode
    anchors.left: true
    anchors.right: true
    anchors.bottom: root.positionMode === "bottom"
    anchors.top: root.positionMode === "top"

    margins {
        bottom: root.positionMode === "bottom" ? 80 : 0
        top: root.positionMode === "top" ? 80 : 0
    }

    // Allow click-through except on text
    mask: Region {}

    // Background gradient for readability (subtle)
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: root.positionMode === "top" ? "#40000000" : "transparent"
            }
            GradientStop {
                position: 0.5
                color: "#20000000"
            }
            GradientStop {
                position: 1.0
                color: root.positionMode === "bottom" ? "#40000000" : "transparent"
            }
        }
    }

    // Main content
    ColumnLayout {
        id: contentColumn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: root.positionMode === "bottom" ? parent.bottom : undefined
        anchors.top: root.positionMode === "top" ? parent.top : undefined
        anchors.verticalCenter: root.positionMode === "center" ? parent.verticalCenter : undefined
        anchors.bottomMargin: 20
        anchors.topMargin: 20
        spacing: 8
        width: parent.width * 0.8

        // Current lyric line (highlighted)
        Text {
            id: currentText
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter

            text: root.currentLine || "♪"
            color: root.textColor
            opacity: root.currentLine ? root.textOpacity : 0.5

            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            font.weight: Font.Bold

            style: Text.Outline
            styleColor: "#80000000"

            wrapMode: Text.WordWrap

            Behavior on text {
                SequentialAnimation {
                    PropertyAnimation {
                        target: currentText
                        property: "opacity"
                        to: 0
                        duration: 150
                    }
                    PropertyAction {
                        target: currentText
                        property: "text"
                    }
                    PropertyAnimation {
                        target: currentText
                        property: "opacity"
                        to: root.textOpacity
                        duration: 150
                    }
                }
            }
        }

        // Upcoming lines (dimmer)
        Repeater {
            model: root.upcomingLines

            delegate: Text {
                required property int index
                required property var modelData

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter

                text: modelData
                color: root.textColor
                opacity: root.textOpacity * (0.6 - index * 0.15)

                font.family: root.fontFamily
                font.pixelSize: root.fontSize * 0.85
                font.weight: Font.Medium

                style: Text.Outline
                styleColor: "#60000000"

                wrapMode: Text.WordWrap
            }
        }
    }

    // Mouse interaction area (invisible overlay)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                // Right click: pause/play
                playerctlProcess.running = true;
            } else {
                // Left click: toggle overlay (close it)
                Qt.quit();
            }
        }
    }

    // Process to run playerctl for pause/play
    Process {
        id: playerctlProcess
        command: ["playerctl", "play-pause"]
        running: false
    }

    // Process to fetch lyrics data
    Process {
        id: lyricsProcess
        command: ["synced-lyrics", "current", "--json", "--lines", root.numLines.toString()]
        running: false

        onExited: function (exitCode, exitStatus) {
            if (exitCode === 0) {
                root.parseLyricsOutput(lyricsProcess.stdout);
            }
            // Schedule next update
            updateTimer.start();
        }
    }

    function parseLyricsOutput(output) {
        try {
            var data = JSON.parse(output.trim());
            if (data.text) {
                root.currentLine = data.text;
            }
            root.isPlaying = data.alt === "playing";

            // Parse tooltip for upcoming lines
            if (data.tooltip) {
                var lines = data.tooltip.split("\n");
                var upcoming = [];
                var foundCurrent = false;

                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i];
                    if (line.startsWith("►") || line.startsWith("<b>►")) {
                        foundCurrent = true;
                        continue;
                    }
                    if (foundCurrent && line.trim() && !line.startsWith("<")) {
                        upcoming.push(line.trim());
                    }
                }
                root.upcomingLines = upcoming.slice(0, root.numLines - 1);
            }
        } catch (e) {
            console.log("Parse error:", e);
        }
    }

    // Timer for periodic updates
    Timer {
        id: updateTimer
        interval: 400
        repeat: false
        onTriggered: {
            lyricsProcess.running = true;
        }
    }

    // Start fetching on load
    Component.onCompleted: {
        lyricsProcess.running = true;
    }
}
