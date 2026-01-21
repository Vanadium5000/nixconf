/*
 * dmenu.qml - Quickshell dmenu/rofi replacement
 *
 * A glassmorphic menu selector implementing Apple's Liquid Glass design language.
 * Reads input from a file (piped via shell wrapper) and outputs selection to stdout.
 *
 * Environment Variables:
 *   DMENU_INPUT_FILE      - Path to file containing menu items (one per line)
 *   DMENU_PROMPT          - Prompt text (default: "Select")
 *   DMENU_LINES           - Number of visible lines (default: 15)
 *   DMENU_PASSWORD        - "true" for password mode (hides input, no list)
 *   DMENU_CASE_INSENSITIVE - "true" for case-insensitive matching
 *   DMENU_SELECTED        - Index of initially selected item
 *   DMENU_PLACEHOLDER     - Placeholder text for empty input
 *   DMENU_FILTER          - Filter mode: "fuzzy", "prefix", "exact"
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "./lib"

Scope {
    id: root

    // =========================================================================
    // Configuration (from environment variables)
    // =========================================================================

    property string inputFile: Quickshell.env("DMENU_INPUT_FILE") ?? ""
    property string promptText: Quickshell.env("DMENU_PROMPT") ?? "Select"
    property int lineCount: parseInt(Quickshell.env("DMENU_LINES") ?? "15")
    property bool passwordMode: (Quickshell.env("DMENU_PASSWORD") ?? "false") === "true"
    property bool caseInsensitive: (Quickshell.env("DMENU_CASE_INSENSITIVE") ?? "true") === "true"
    property int selectedIndex: parseInt(Quickshell.env("DMENU_SELECTED") ?? "0")
    property string placeholderText: Quickshell.env("DMENU_PLACEHOLDER") ?? ""
    property string filterMode: Quickshell.env("DMENU_FILTER") ?? "fuzzy"

    // Track loading state
    property bool isLoading: true

    // =========================================================================
    // Data Models
    // =========================================================================

    ListModel { id: itemsModel }
    ListModel { id: filteredModel }

    // =========================================================================
    // File Reader - Uses Quickshell.Io.Process with SplitParser
    // =========================================================================

    Process {
        id: fileReader
        command: ["cat", root.inputFile]
        running: false  // Start manually after component is ready

        stdout: SplitParser {
            onRead: data => {
                if (data.trim() !== "") {
                    var parsed = root.parseLine(data);
                    itemsModel.append(parsed);
                    filteredModel.append(parsed);
                }
            }
        }

        onExited: (code, status) => {
            root.isLoading = false;
            // Set initial selection after loading
            if (root.selectedIndex > 0 && root.selectedIndex < filteredModel.count) {
                listView.currentIndex = root.selectedIndex;
            }
        }
    }

    // Start file reader after component is fully loaded
    Component.onCompleted: {
        if (root.inputFile !== "") {
            fileReader.running = true;
        } else {
            root.isLoading = false;
        }
    }

    // =========================================================================
    // Main Window
    // =========================================================================

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

        // ---------------------------------------------------------------------
        // Backdrop - Semi-transparent overlay with click-to-dismiss
        // ---------------------------------------------------------------------
        Rectangle {
            anchors.fill: parent
            // Apple-style dark backdrop
            color: Qt.rgba(0, 0, 0, 0.4)

            MouseArea {
                anchors.fill: parent
                onClicked: Qt.quit()
            }
        }

        // ---------------------------------------------------------------------
        // Main Dialog Container - Liquid Glass Panel
        // ---------------------------------------------------------------------
        Item {
            id: mainDialog
            anchors.centerIn: parent
            width: 600
            height: Math.min(520, 76 + (root.lineCount * 44))

            // Outer glow (subtle accent border outside main container)
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                radius: Theme.glass.cornerRadius + 1
                color: "transparent"
                border.color: Qt.rgba(
                    Theme.glass.accentColor.r,
                    Theme.glass.accentColor.g,
                    Theme.glass.accentColor.b,
                    0.12
                )
                border.width: 1
            }

            // Main glass container
            Rectangle {
                id: glassContainer
                anchors.fill: parent
                radius: Theme.glass.cornerRadius

                // Base glass material - Apple dark mode values
                color: Theme.glass.backgroundColor

                // Specular highlight gradient (top 40% of panel)
                Rectangle {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 1
                    }
                    height: parent.height * 0.4
                    radius: Theme.glass.cornerRadius - 1

                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(1, 1, 1, Theme.glass.highlightOpacity)
                        }
                        GradientStop {
                            position: 0.35
                            color: Qt.rgba(1, 1, 1, Theme.glass.highlightOpacity * 0.3)
                        }
                        GradientStop {
                            position: 1.0
                            color: "transparent"
                        }
                    }
                }

                // Inner stroke (cut-glass depth effect)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: Theme.glass.cornerRadius - 1
                    color: "transparent"
                    border.color: Theme.glass.innerStrokeColor
                    border.width: 1
                }

                // Accent border
                border.color: Qt.rgba(
                    Theme.glass.accentColor.r,
                    Theme.glass.accentColor.g,
                    Theme.glass.accentColor.b,
                    Theme.glass.borderOpacity
                )
                border.width: 1

                // -----------------------------------------------------------------
                // Content Layout
                // -----------------------------------------------------------------
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.glass.padding
                    spacing: Theme.glass.itemSpacing

                    // Search Bar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 50
                        radius: Theme.glass.cornerRadius - 4
                        color: Qt.rgba(0, 0, 0, 0.35)

                        // Inner highlight
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: parent.radius - 1
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.04)
                            border.width: 1
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            // Prompt label
                            Text {
                                text: root.promptText
                                font.family: Theme.glass.fontFamily
                                font.pixelSize: Theme.glass.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: Theme.glass.accentColor
                            }

                            // Vertical divider
                            Rectangle {
                                width: 1
                                Layout.fillHeight: true
                                Layout.topMargin: 12
                                Layout.bottomMargin: 12
                                color: Qt.rgba(1, 1, 1, 0.12)
                            }

                            // Text input field
                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: Theme.glass.fontFamily
                                font.pixelSize: Theme.glass.fontSizeMedium
                                color: Theme.glass.textPrimary
                                focus: true
                                clip: true
                                selectByMouse: true
                                selectionColor: Theme.glass.accentColor
                                selectedTextColor: "#ffffff"

                                echoMode: root.passwordMode ? TextInput.Password : TextInput.Normal

                                // Placeholder text
                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 2
                                    verticalAlignment: Text.AlignVCenter
                                    text: root.placeholderText || (root.passwordMode ? "Enter password..." : "Type to filter...")
                                    color: Theme.glass.textTertiary
                                    font: parent.font
                                    visible: !parent.text && !parent.activeFocus
                                }

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
                                    if (filteredModel.count > 0) {
                                        listView.currentIndex = 0;
                                    }
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
                                        if (filteredModel.count > 0 && listView.currentIndex >= 0) {
                                            var item = filteredModel.get(listView.currentIndex);
                                            searchInput.text = item.displayText;
                                        }
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_PageDown) {
                                        listView.currentIndex = Math.min(
                                            listView.currentIndex + 5,
                                            filteredModel.count - 1
                                        );
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_PageUp) {
                                        listView.currentIndex = Math.max(listView.currentIndex - 5, 0);
                                        event.accepted = true;
                                    }
                                }
                            }

                            // Match count indicator
                            Text {
                                text: filteredModel.count + "/" + itemsModel.count
                                font.family: Theme.glass.fontFamily
                                font.pixelSize: Theme.glass.fontSizeSmall
                                color: Theme.glass.textTertiary
                                visible: !root.passwordMode && itemsModel.count > 0
                            }
                        }
                    }

                    // Results ListView
                    ListView {
                        id: listView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        visible: !root.passwordMode

                        model: filteredModel

                        // Empty/loading state indicator
                        Text {
                            anchors.centerIn: parent
                            text: root.isLoading ? "Loading..." : "No matches"
                            color: Theme.glass.textTertiary
                            font.family: Theme.glass.fontFamily
                            font.pixelSize: Theme.glass.fontSizeMedium
                            visible: listView.count === 0
                        }

                        delegate: Rectangle {
                            id: delegateItem
                            width: listView.width
                            height: 40
                            radius: Theme.glass.cornerRadius - 6

                            property bool isSelected: index === listView.currentIndex
                            property bool isHovered: delegateMouseArea.containsMouse

                            // Glass button styling based on state
                            color: {
                                if (isSelected) {
                                    return Qt.rgba(
                                        Theme.glass.accentColor.r,
                                        Theme.glass.accentColor.g,
                                        Theme.glass.accentColor.b,
                                        0.32
                                    );
                                }
                                if (isHovered) {
                                    return Qt.rgba(1, 1, 1, 0.06);
                                }
                                return Qt.rgba(1, 1, 1, 0.02);
                            }

                            border.color: {
                                if (isSelected) {
                                    return Qt.rgba(
                                        Theme.glass.accentColor.r,
                                        Theme.glass.accentColor.g,
                                        Theme.glass.accentColor.b,
                                        0.5
                                    );
                                }
                                if (isHovered) {
                                    return Qt.rgba(1, 1, 1, 0.1);
                                }
                                return "transparent";
                            }
                            border.width: (isSelected || isHovered) ? 1 : 0

                            Behavior on color {
                                ColorAnimation { duration: Theme.glass.animationDuration }
                            }

                            // Top highlight for glass effect
                            Rectangle {
                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                    margins: 1
                                }
                                height: parent.height * 0.5
                                radius: parent.radius - 1
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0
                                        color: Qt.rgba(1, 1, 1, delegateItem.isSelected ? 0.1 : 0.03)
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: "transparent"
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 10

                                // Icon (if present)
                                Text {
                                    visible: (model.iconPath || "") !== ""
                                    text: model.iconPath || ""
                                    font.family: Theme.glass.fontFamily
                                    font.pixelSize: 16
                                    color: delegateItem.isSelected
                                        ? Theme.glass.accentColorAlt
                                        : Theme.glass.textSecondary
                                }

                                // Label
                                Text {
                                    Layout.fillWidth: true
                                    text: model.displayText || ""
                                    font.family: Theme.glass.fontFamily
                                    font.pixelSize: Theme.glass.fontSizeMedium
                                    font.weight: delegateItem.isSelected ? Font.Medium : Font.Normal
                                    color: delegateItem.isSelected
                                        ? Theme.glass.textPrimary
                                        : Theme.glass.textSecondary
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: delegateMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    outputAndQuit(model.originalText || model.text);
                                }
                            }
                        }

                        highlightFollowsCurrentItem: true
                        highlightMoveDuration: 50

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            width: 5
                            contentItem: Rectangle {
                                radius: 2.5
                                color: Qt.rgba(1, 1, 1, 0.25)
                            }
                        }
                    }
                }
            }

            // Drop shadow (positioned behind glass container)
            Rectangle {
                anchors.fill: glassContainer
                anchors.topMargin: Theme.glass.shadowOffsetY
                z: -1
                radius: Theme.glass.cornerRadius
                color: Qt.rgba(0, 0, 0, Theme.glass.shadowOpacity)
            }
        }
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    /**
     * Output the selected text to stdout and exit.
     * The shell wrapper strips the "qml: " prefix.
     */
    function outputAndQuit(text) {
        console.log(text);
        Qt.quit();
    }

    /**
     * Parse a line of input, extracting icon if present.
     * Supports Rofi's icon format: Text\0icon\x1fIconPath
     */
    function parseLine(line) {
        var text = line;
        var icon = "";

        // Handle Rofi icon format
        var iconMarker = "\0icon\x1f";
        var iconIdx = line.indexOf(iconMarker);
        if (iconIdx !== -1) {
            text = line.substring(0, iconIdx);
            icon = line.substring(iconIdx + iconMarker.length).trim();
        }

        // Strip Pango/HTML markup for display
        var displayText = text.replace(/<[^>]*>/g, "");

        return {
            text: text,
            originalText: line,
            displayText: displayText,
            iconPath: icon
        };
    }

    /**
     * Filter items based on query string.
     * Supports fuzzy (contains), prefix, and exact matching.
     */
    function filterItems(query) {
        filteredModel.clear();

        // No filter - show all items
        if (query === "") {
            for (var i = 0; i < itemsModel.count; i++) {
                filteredModel.append(itemsModel.get(i));
            }
            return;
        }

        var q = root.caseInsensitive ? query.toLowerCase() : query;

        for (var j = 0; j < itemsModel.count; j++) {
            var item = itemsModel.get(j);
            var t = root.caseInsensitive ? item.text.toLowerCase() : item.text;

            var match = false;
            if (root.filterMode === "prefix") {
                match = t.indexOf(q) === 0;
            } else if (root.filterMode === "exact") {
                match = t === q;
            } else {
                // fuzzy (contains)
                match = t.indexOf(q) !== -1;
            }

            if (match) {
                filteredModel.append(item);
            }
        }
    }
}
