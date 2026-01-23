/*
 * launcher.qml - Application Launcher & Calculator
 *
 * Floating centered window implementing the Liquid Glass design.
 * Features:
 * - Application search (via desktop files)
 * - Calculator mode (via qalc)
 * - Single instance locking (toggleable)
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./lib"

Scope {
    id: root

    // --- State ---
    property string mode: searchInput.text.startsWith("=") ? "calc" : "app"

    // --- Single Instance Lock ---
    InstanceLock {
        lockName: "launcher"
        toggle: true
    }

    // --- Window Configuration ---
    // Fullscreen overlay window to allow centering content
    PanelWindow {
        id: window
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        visible: true

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        color: "transparent"

        // Close on click outside
        MouseArea {
            anchors.fill: parent
            onClicked: Qt.quit()
        }

        // Centered Content Container
        Item {
            width: 600
            height: root.mode === "calc" ? 200 : 500
            anchors.centerIn: parent

            // Block clicks from closing window when clicking inside content
            MouseArea {
                anchors.fill: parent
                onClicked: mouse.accepted = false
            }

            GlassPanel {
                anchors.fill: parent
                hasShadow: true
                hasBlur: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.gapsOut
                    spacing: Theme.gapsIn

                    // --- Search Bar ---
                    GlassPanel {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 50
                        cornerRadius: Theme.rounding
                        opacityValue: 0.3

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            anchors.margins: 10
                            verticalAlignment: TextInput.AlignVCenter

                            font.family: Theme.fontName
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.foreground

                            text: ""
                            focus: true

                            property string placeholder: root.mode === "calc" ? "Calculate..." : "Search Applications..."

                            Text {
                                anchors.fill: parent
                                text: searchInput.placeholder
                                color: Theme.rgba(Theme.foreground, 0.5)
                                font: searchInput.font
                                verticalAlignment: TextInput.AlignVCenter
                                visible: !searchInput.text && !searchInput.activeFocus
                            }

                            onAccepted: {
                                if (root.mode === "calc") {
                                    // Copy result to clipboard
                                    if (calcResult.text !== "") {
                                        var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["wl-copy", "' + calcResult.text + '"]; running: true }', root);
                                        Qt.quit();
                                    }
                                } else {
                                    if (appModel.count > 0) {
                                        runner.command = [appModel.get(0).exec];
                                        runner.running = true;
                                        Qt.quit();
                                    }
                                }
                            }

                            onTextChanged: {
                                if (root.mode === "app") {
                                    appSearcher.running = true;
                                } else if (root.mode === "calc") {
                                    calcRunner.running = true;
                                }
                            }
                        }
                    }

                    // --- Calc Result (Calc Mode) ---
                    GlassPanel {
                        visible: root.mode === "calc"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        cornerRadius: Theme.rounding
                        opacityValue: 0.3

                        Text {
                            id: calcResult
                            anchors.fill: parent
                            anchors.margins: 10
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignRight

                            font.family: Theme.fontName
                            font.pixelSize: 24
                            color: Theme.accent
                            font.bold: true
                            text: ""
                        }
                    }

                    // --- App Grid/List (App Mode) ---
                    ListView {
                        id: appView
                        visible: root.mode === "app"

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4

                        model: ListModel {
                            id: appModel
                        }

                        delegate: GlassButton {
                            width: appView.width
                            height: 50
                            text: model.name
                            // Use exec command to resolve icon (often matches binary name), fallback to name
                            // GlassButton handles the fallback to terminal if it fails
                            iconSource: model.exec.split(" ")[0]
                            active: index === 0 // Highlight first match

                            // Liquid Glass hover effect
                            opacity: hovered ? 1.0 : 0.8
                            
                            onClicked: {
                                runner.command = [model.exec];
                                runner.running = true;
                                Qt.quit();
                            }
                        }
                    }
                }
            }

            // Close on escape
            Shortcut {
                sequence: "Escape"
                onActivated: Qt.quit()
            }
        }

        // --- Application Search Logic ---
        // Using a Process to grep desktop files.
        // In a production environment, we'd want a proper indexed service or a C++ plugin.
        // For now, we'll use a simple shell pipeline to find .desktop files and parse names.

        Process {
            id: appSearcher
            // Find .desktop files using a robust awk script to pair Name and Exec
            // safely handling file boundaries and missing fields.
            // Search case-insensitive, limit to top 20 results for performance.
            command: [
                "bash", "-c", 
                "find /run/current-system/sw/share/applications -name '*.desktop' -print0 | " +
                "xargs -0 awk -F= '" +
                "FNR==1 {if(n&&e) print n\"\\t\"e; n=\"\"; e=\"\"} " +
                "/^Name=/{n=substr($0,6)} " +
                "/^Exec=/{e=substr($0,6)} " +
                "END {if(n&&e) print n\"\\t\"e}' | " +
                "grep -i '" + searchInput.text + "' | head -n 20"
            ]

            stdout: StdioCollector {
                onStreamFinished: {
                    appModel.clear();
                    var lines = text.split("\n");
                    for (var i = 0; i < lines.length; i++) {
                        var line = lines[i].trim();
                        if (!line)
                            continue;

                        // Expecting: Name=Firefox\tExec=firefox %u
                        var parts = line.split("\t");
                        if (parts.length >= 2) {
                            var name = parts[0].replace("Name=", "");
                            var exec = parts[1].replace("Exec=", "").replace(/%[fFuU]/, "").trim();

                            appModel.append({
                                "name": name,
                                "exec": exec
                            });
                        }
                    }
                }
            }
        }

        Process {
            id: calcRunner
            command: ["qalc", "-t", searchInput.text]
            running: false
            stdout: StdioCollector {
                onStreamFinished: {
                    // qalc -t returns "expression = result"
                    // We just want the result usually, or the whole thing.
                    // qalc -t outputs simple text.
                    calcResult.text = text.trim();
                }
            }
        }

        Process {
            id: runner
            running: false
            onExited: Qt.quit()
        }
    }
}
