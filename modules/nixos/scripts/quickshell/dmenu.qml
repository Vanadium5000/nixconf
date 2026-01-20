import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "./lib"

Scope {
    id: root

    // --- Configuration ---
    property string inputFile: Quickshell.env("DMENU_INPUT_FILE") ?? ""
    property string promptText: Quickshell.env("DMENU_PROMPT") ?? "Select"
    property int lineCount: parseInt(Quickshell.env("DMENU_LINES") ?? "10")
    property bool passwordMode: (Quickshell.env("DMENU_PASSWORD") ?? "false") === "true"

    // --- Data Model ---
    ListModel { id: itemsModel }
    ListModel { id: filteredModel }

    // --- Window ---
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

        // Semi-transparent backdrop
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.3)

            MouseArea {
                anchors.fill: parent
                onClicked: Qt.quit()
            }
        }

        // Main dialog
        GlassPanel {
            anchors.centerIn: parent
            width: 600
            height: Math.min(500, 70 + (root.lineCount * 44))
            hasShadow: true
            cornerRadius: Theme.roundingLarge

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.gapsOut
                spacing: Theme.gapsIn

                // --- Search / Prompt Bar ---
                GlassPanel {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    cornerRadius: Theme.rounding
                    opacityValue: 0.4
                    hasBorder: false

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        Text {
                            text: root.promptText
                            font.family: Theme.fontName
                            font.pixelSize: Theme.fontSizeLarge
                            font.bold: true
                            color: Theme.accent
                        }

                        Rectangle {
                            width: 1
                            Layout.fillHeight: true
                            Layout.topMargin: 12
                            Layout.bottomMargin: 12
                            color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.3)
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Theme.fontName
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.foreground
                            focus: true
                            clip: true

                            echoMode: root.passwordMode ? TextInput.Password : TextInput.Normal

                            onAccepted: {
                                var result = "";
                                if (filteredModel.count > 0 && listView.currentIndex >= 0) {
                                    var item = filteredModel.get(listView.currentIndex);
                                    result = item.originalText || item.text;
                                } else if (text) {
                                    result = text;
                                }
                                if (result) outputAndQuit(result);
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
                                } else if (event.key === Qt.Key_Tab) {
                                    // Tab completion
                                    if (filteredModel.count > 0 && listView.currentIndex >= 0) {
                                        var item = filteredModel.get(listView.currentIndex);
                                        searchInput.text = item.displayText;
                                    }
                                    event.accepted = true;
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
                    spacing: 4
                    visible: !root.passwordMode

                    model: filteredModel

                    // Empty state
                    Text {
                        anchors.centerIn: parent
                        text: root.inputFile ? "No matches" : "Loading..."
                        color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.4)
                        font.family: Theme.fontName
                        font.pixelSize: Theme.fontSize
                        visible: listView.count === 0
                    }

                    delegate: GlassButton {
                        width: listView.width
                        height: 40
                        text: model.displayText
                        icon: model.iconPath || ""
                        active: index === listView.currentIndex

                        onClicked: {
                            outputAndQuit(model.originalText || model.text);
                        }
                    }

                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: 80
                }
            }
        }
    }

    // --- Logic ---
    function outputAndQuit(text) {
        console.log(text);
        Qt.quit();
    }

    function parseLine(line) {
        var text = line;
        var icon = "";

        // Handle Rofi icon format: Text\0icon\x1fPath
        if (line.includes("\0icon\x1f")) {
            var parts = line.split("\0icon\x1f");
            text = parts[0];
            icon = parts[1] ? parts[1].trim() : "";
        }

        // Strip basic markup for display
        var displayText = text.replace(/<[^>]*>/g, "");

        return {
            text: text,
            originalText: line,
            displayText: displayText,
            iconPath: icon
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

    // Read input file on load
    Component.onCompleted: {
        if (root.inputFile) {
            var xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    var lines = xhr.responseText.split("\n");
                    for (var i = 0; i < lines.length; i++) {
                        if (lines[i].trim() !== "") {
                            var parsed = parseLine(lines[i]);
                            itemsModel.append(parsed);
                            filteredModel.append(parsed);
                        }
                    }
                }
            };
            xhr.open("GET", "file://" + root.inputFile);
            xhr.send();
        }
    }
}
