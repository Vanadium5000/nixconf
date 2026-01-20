import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "./lib"

Scope {
    id: root

    // --- Configuration ---
    // Reads input from a file specified by env var (simulating stdin)
    property string inputFile: Quickshell.env("DMENU_INPUT_FILE") ?? ""
    property string promptText: Quickshell.env("DMENU_PROMPT") ?? "Select"
    property int lineCount: parseInt(Quickshell.env("DMENU_LINES") ?? "10")

    property bool passwordMode: (Quickshell.env("DMENU_PASSWORD") ?? "false") === "true"

    // --- Data Model ---
    ListModel {
        id: itemsModel
    }

    // --- Window ---
    PanelWindow {
        id: window
        anchors.centerIn: parent
        width: 600
        height: Math.min(600, 60 + (root.lineCount * 40)) // Dynamic height
        visible: true

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        color: "transparent"

        GlassPanel {
            anchors.fill: parent
            hasShadow: true
            hasBlur: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.gapsOut
                spacing: Theme.gapsIn

                // --- Search / Prompt ---
                GlassPanel {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    cornerRadius: Theme.rounding
                    opacityValue: 0.3

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Text {
                            text: root.promptText
                            font.family: Theme.fontName
                            font.pixelSize: Theme.fontSizeLarge
                            font.bold: true
                            color: Theme.accent
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.family: Theme.fontName
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.foreground
                            focus: true

                            echoMode: root.passwordMode ? TextInput.Password : TextInput.Normal

                            onAccepted: {
                                // Output selected or typed
                                var result = "";
                                if (filteredModel.count > 0 && listView.currentIndex >= 0 && !text) {
                                    result = filteredModel.get(listView.currentIndex).originalText || filteredModel.get(listView.currentIndex).text;
                                } else {
                                    result = text;
                                }
                                outputAndQuit(result);
                            }

                            onTextChanged: {
                                filterItems(text);
                                listView.currentIndex = 0;
                            }

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Down) {
                                    listView.incrementCurrentIndex();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up) {
                                    listView.decrementCurrentIndex();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    Qt.quit();
                                }
                            }
                        }
                    }
                }

                // --- List View ---
                ListView {
                    id: listView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    visible: !root.passwordMode // Hide list in password mode usually

                    model: ListModel {
                        id: filteredModel
                    }

                    highlight: Rectangle {
                        color: Theme.rgba(Theme.accent, 0.2)
                        radius: Theme.rounding
                    }
                    highlightMoveDuration: 100

                    delegate: Item {
                        width: listView.width
                        height: 40

                        GlassButton {
                            anchors.fill: parent
                            text: model.displayText
                            icon: model.iconPath
                            active: ListView.isCurrentItem

                            onClicked: {
                                outputAndQuit(model.originalText || model.text);
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Logic ---

    function outputAndQuit(text) {
        // Output to stdout via console.log (wrapper should handle stderr/stdout separation)
        console.log(text);
        Qt.quit();
    }

    function parseLine(line) {
        // Handle Rofi icon format: Text\0icon\x1fPath
        var text = line;
        var icon = "";

        if (line.includes("\0icon\x1f")) {
            var parts = line.split("\0icon\x1f");
            text = parts[0];
            icon = parts[1] ? parts[1].trim() : "";
        }

        // Handle basic Pango markup removal for display (very basic)
        var displayText = text.replace(/<[^>]*>/g, "");

        return {
            "text": text // For filtering
            ,
            "originalText": line // For output (preserve original)
            ,
            "displayText": displayText // For UI
            ,
            "iconPath": icon
        };
    }

    function filterItems(query) {
        filteredModel.clear();
        var lowerQuery = query.toLowerCase();

        for (var i = 0; i < itemsModel.count; i++) {
            var item = itemsModel.get(i);
            if (item.text.toLowerCase().indexOf(lowerQuery) !== -1) {
                filteredModel.append(item);
            }
        }
    }

    // Read input file
    Component.onCompleted: {
        if (root.inputFile) {
            var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["cat", "' + root.inputFile + '"]; running: true }', root);
            proc.stdout.onStreamFinished.connect(() => {
                var lines = proc.stdout.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].trim() !== "") {
                        var parsed = parseLine(lines[i]);
                        itemsModel.append(parsed);
                        filteredModel.append(parsed); // Initial populate
                    }
                }
            });
        }
    }
}
