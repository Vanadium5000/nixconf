/*
 * lyrics-overlay.qml - Synced Lyrics Display
 *
 * Floating overlay that displays synchronized lyrics from a data source.
 * Typically driven by 'synced-lyrics' or compatible MPRIS wrappers.
 *
 * Features:
 * - Karaoke-style line highlighting
 * - Upcoming lines preview
 * - Compact click-through card surface
 * - Configurable positioning (Top/Bottom/Center)
 */

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import Qt5Compat.GraphicalEffects
import "./lib"

PanelWindow {
    id: root
    
    InstanceLock {
        lockName: "lyrics"
        toggle: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // --- Configuration ---
    // Read from environment variables with sensible defaults
    property int numLines: parseInt(Quickshell.env("LYRICS_LINES") ?? "3")
    property string positionMode: Quickshell.env("LYRICS_POSITION") ?? "bottom"
    property int fontSize: parseInt(Quickshell.env("LYRICS_FONT_SIZE") ?? Theme.fontSizeLarge.toString())
    property string textColor: Quickshell.env("LYRICS_COLOR") ?? Theme.foreground
    property real textOpacity: parseFloat(Quickshell.env("LYRICS_OPACITY") ?? "0.95")
    property string fontFamily: Quickshell.env("LYRICS_FONT") ?? Theme.fontName
    property bool showShadow: (Quickshell.env("LYRICS_SHADOW") ?? "true") === "true"
    property int lineSpacing: parseInt(Quickshell.env("LYRICS_SPACING") ?? "8")
    property int maxLineLength: parseInt(Quickshell.env("LYRICS_LENGTH") ?? "0")
    property int cardMaxWidth: 520 // Keeps the lyrics card compact so it does not dominate the desktop.
    property int cardInset: 24 // Small gutters prevent edge-to-edge coverage on wide monitors.
    property int cardRadius: 20
    property int edgeOffset: 56 // Sits above the dock/shelf without floating too far from the player.
    property int cardPadding: 14
    property int availableWidth: Math.max(0, (screen ? screen.width : root.cardMaxWidth) - root.cardInset * 2)

    // --- State ---
    property string currentLine: ""
    property var upcomingLines: []
    property string trackInfo: ""
    property bool isPlaying: false

    // --- Window Layout ---
    implicitWidth: Math.min(root.availableWidth, root.cardMaxWidth)
    implicitHeight: contentColumn.implicitHeight + root.cardPadding * 2
    color: "transparent"

    // Keep the overlay decorative only; it should not reserve space or grab focus.
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    // Dynamic anchoring based on configuration
    anchors.left: true
    anchors.bottom: root.positionMode === "bottom"
    anchors.top: root.positionMode !== "bottom"

    margins {
        left: screen ? Math.max(0, Math.round((screen.width - implicitWidth) / 2)) : 0
        top: root.positionMode === "bottom"
            ? 0
            : root.positionMode === "top"
                ? root.edgeOffset
                : screen ? Math.max(0, Math.round((screen.height - implicitHeight) / 2)) : root.edgeOffset
        bottom: root.positionMode === "bottom" ? root.edgeOffset : 0
    }

    // Compact card keeps the visible surface bounded to the lyric content.
    Item {
        id: contentCard
        anchors.fill: parent
        implicitHeight: contentColumn.implicitHeight + root.cardPadding * 2

        Rectangle {
            id: cardBackground
            anchors.fill: parent
            radius: root.cardRadius
            color: Theme.glass.backgroundColor
            border.width: 1
            border.color: Theme.rgba(Theme.glass.accentColor, 0.18)
            clip: true
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 1
            }
            height: 1
            radius: 0
            color: Theme.rgba(Theme.glass.accentColor, 0.16)
        }

        DropShadow {
            anchors.fill: cardBackground
            source: cardBackground
            visible: root.showShadow
            z: -1
            horizontalOffset: 0
            verticalOffset: 8
            radius: 14
            samples: 25
            color: Qt.rgba(0, 0, 0, 0.35)
        }

        Column {
            id: contentColumn
            anchors {
                fill: parent
                margins: root.cardPadding
            }
            spacing: Math.max(4, root.lineSpacing - 2)

            Text {
                id: currentText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.currentLine || "♪"
                color: root.textColor
                opacity: root.currentLine ? root.textOpacity : 0.5
                font.family: root.fontFamily
                font.pixelSize: root.fontSize
                font.weight: Font.Bold
                style: root.showShadow ? Text.Outline : Text.Normal
                styleColor: "#80000000"
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight

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
                            to: root.currentLine ? root.textOpacity : 0.5
                            duration: 150
                        }
                    }
                }
            }

            Repeater {
                model: root.upcomingLines

                delegate: Text {
                    required property int index
                    required property var modelData

                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: root.textColor
                    opacity: Math.max(0.2, root.textOpacity * (0.58 - index * 0.12))
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(16, Math.round(root.fontSize * 0.72))
                    font.weight: Font.Medium
                    style: root.showShadow ? Text.Outline : Text.Normal
                    styleColor: "#60000000"
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            onClicked: function (mouse) {
                if (mouse.button === Qt.RightButton) {
                    playerctlProcess.running = true
                    return
                }

                Qt.quit()
            }
        }
    }

    Process {
        id: playerctlProcess
        command: ["playerctl", "play-pause"]
        running: false
    }

    // Process to fetch lyrics data
    Process {
        id: lyricsProcess
        command: Quickshell.env("OVERLAY_COMMAND") 
            ? Quickshell.env("OVERLAY_COMMAND").split(" ") 
            : ["synced-lyrics", "current", "--json", "--lines", root.numLines.toString(), "--length", root.maxLineLength.toString()]
        running: false

        stdout: StdioCollector {
            id: stdoutCollector
            onStreamFinished: {
                root.parseLyricsOutput(stdoutCollector.text);
                // Schedule next update
                updateTimer.start();
            }
        }

        onExited: function (exitCode, exitStatus) {
            // If process exits without streamFinished (error case), still schedule next update
            if (exitCode !== 0) {
                updateTimer.start();
            }
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
        interval: parseInt(Quickshell.env("LYRICS_UPDATE_INTERVAL") ?? "400")
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
