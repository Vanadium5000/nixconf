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

    property var allApps: []
    property var filteredApps: []

    function filterApps() {
        var query = searchInput.text.toLowerCase();
        if (query === "") {
            filteredApps = allApps;
        } else {
            filteredApps = allApps.filter(function (app) {
                return app.name.toLowerCase().indexOf(query) >= 0;
            });
        }
        appModel.clear();
        for (var i = 0; i < filteredApps.length; i++) {
            appModel.append(filteredApps[i]);
        }
        appView.currentIndex = 0;
    }

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
                        cornerRadius: Theme.glass.cornerRadiusSmall
                        opacityValue: 0.3

                        TextInput {
                            id: searchInput
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14

                            font.family: Theme.fontName
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.foreground

                            text: ""
                            focus: true
                            clip: false

                            property string placeholder: root.mode === "calc" ? "Calculate..." : "Search Applications..."

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: searchInput.placeholder
                                color: Theme.rgba(Theme.foreground, 0.5)
                                font: searchInput.font
                                visible: !searchInput.text && !searchInput.activeFocus
                            }

                            Keys.onUpPressed: appView.decrementCurrentIndex()
                            Keys.onDownPressed: appView.incrementCurrentIndex()

                            onAccepted: {
                                if (root.mode === "calc") {
                                    // Copy result to clipboard
                                    if (calcResult.text !== "") {
                                        var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["wl-copy", "' + calcResult.text + '"]; running: true }', root);
                                        Qt.quit();
                                    }
                                } else {
                                    if (appModel.count > 0) {
                                        var item = appModel.get(appView.currentIndex);
                                        runner.command = ["setsid", "-f"].concat(item.exec.split(" "));
                                        runner.running = true;
                                        Qt.quit();
                                    }
                                }
                            }

                            onTextChanged: {
                                if (root.mode === "app") {
                                    root.filterApps();
                                } else if (root.mode === "calc") {
                                    var expr = text.substring(1).trim();
                                    if (expr.length > 0) {
                                        calcRunner.command = ["qalc", "-t", expr];
                                        calcRunner.running = true;
                                    } else {
                                        calcResult.text = "";
                                    }
                                }
                            }
                        }
                    }

                    // --- Calc Result (Calc Mode) ---
                    GlassPanel {
                        visible: root.mode === "calc"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        cornerRadius: Theme.glass.cornerRadiusSmall
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
                        spacing: 2

                        model: ListModel {
                            id: appModel
                        }

                        delegate: Column {
                            width: appView.width
                            spacing: 1

                            property bool expanded: false
                            property var appActions: model.actions ? model.actions : []

                            GlassButton {
                                width: parent.width
                                height: 44
                                text: model.name
                                contentAlignment: Qt.AlignLeft
                                iconSource: model.icon
                                active: appView.currentIndex === index

                                opacity: hovered ? 1.0 : 0.85

                                onClicked: {
                                    appView.currentIndex = index;
                                    runner.command = ["setsid", "-f"].concat(model.exec.split(" "));
                                    runner.running = true;
                                    Qt.quit();
                                }

                                onRightClicked: {
                                    if (appActions.length > 0) {
                                        expanded = !expanded;
                                    }
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: appActions.length > 0 ? (expanded ? "▲" : "▼") : ""
                                    color: Theme.foreground
                                    font.pixelSize: 10
                                    opacity: 0.5
                                }
                            }

                            Repeater {
                                model: expanded ? appActions : []

                                GlassButton {
                                    width: parent.width - 24
                                    x: 24
                                    height: 36
                                    text: modelData.name
                                    contentAlignment: Qt.AlignLeft
                                    iconSource: ""
                                    opacity: hovered ? 1.0 : 0.7
                                    cornerRadius: 8

                                    onClicked: {
                                        runner.command = ["setsid", "-f"].concat(modelData.exec.split(" "));
                                        runner.running = true;
                                        Qt.quit();
                                    }
                                }
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

        Component.onCompleted: appLoader.running = true

        Process {
            id: appLoader
            // Script path is passed via environment variable from the wrapper,
            // falling back to resolving relative to QML file location
            property string scriptPath: Quickshell.env("LAUNCHER_SCRIPT_DIR") 
                ? Quickshell.env("LAUNCHER_SCRIPT_DIR") + "/list_apps.ts"
                : Qt.resolvedUrl("list_apps.ts").toString().replace("file://", "")
            
            command: ["bun", scriptPath]

            stdout: StdioCollector {
                id: appCollector
            }
            
            stderr: StdioCollector {
                id: appErrorCollector
            }

            onExited: exitCode => {
                if (exitCode !== 0) {
                    console.error("[Launcher] appLoader failed with exit code: " + exitCode);
                    if (appErrorCollector.text) {
                        console.error("[Launcher] stderr: " + appErrorCollector.text);
                    }
                    console.error("[Launcher] Attempted script path: " + scriptPath);
                    return;
                }
                
                console.debug("[Launcher] Loaded " + appCollector.text.split("\n").length + " lines from list_apps.ts");

                root.allApps = [];
                var lines = appCollector.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (!line)
                        continue;

                    var parts = line.split("\t");
                    if (parts.length >= 2) {
                        var actions = [];
                        if (parts.length > 3 && parts[3]) {
                            try {
                                actions = JSON.parse(parts[3]);
                            } catch (e) {}
                        }
                        root.allApps.push({
                            "name": parts[0],
                            "exec": parts[1],
                            "icon": parts.length > 2 ? parts[2] : "",
                            "actions": actions
                        });
                    }
                }
                root.filterApps();
            }
        }

        Process {
            id: calcRunner
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
