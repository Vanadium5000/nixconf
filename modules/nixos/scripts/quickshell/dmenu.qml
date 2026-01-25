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
    property string messageText: Quickshell.env("DMENU_MESSAGE") ?? ""
    property string filterMode: Quickshell.env("DMENU_FILTER") ?? "fuzzy"
    property string viewMode: Quickshell.env("DMENU_VIEW") ?? "list" // list, grid
    property int gridColumns: parseInt(Quickshell.env("DMENU_GRID_COLS") ?? "3")
    property int gridIconSize: parseInt(Quickshell.env("DMENU_ICON_SIZE") ?? "128")

    // Track loading state
    property bool isLoading: true

    InstanceLock {
        lockName: "dmenu"
    }

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
            if (root.selectedIndex > 0 && root.selectedIndex < filteredModel.count && viewLoader.item) {
                viewLoader.item.currentIndex = root.selectedIndex;
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
            width: root.viewMode === "grid" ? Math.min(parent.width * 0.9, 900) : 600
            height: root.viewMode === "grid" ? Math.min(parent.height * 0.85, 700) : Math.min(520, 76 + (root.lineCount * 44))

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
                                    var item = viewLoader.getCurrentItem();
                                    if (item) {
                                        result = item.originalText || item.text;
                                    } else if (text) {
                                        result = text;
                                    }
                                    if (result) outputAndQuit(result);
                                }

                                onTextChanged: {
                                    filterItems(text);
                                    if (filteredModel.count > 0 && viewLoader.item) {
                                        viewLoader.item.currentIndex = 0;
                                    }
                                }

                                Keys.onPressed: event => {
                                    if (event.key === Qt.Key_Down) {
                                        viewLoader.increment();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Up) {
                                        viewLoader.decrement();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_Escape) {
                                        Qt.quit();
                                    } else if (event.key === Qt.Key_Tab) {
                                        var item = viewLoader.getCurrentItem();
                                        if (item) {
                                            searchInput.text = item.displayText;
                                        }
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_PageDown) {
                                        viewLoader.pageDown();
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_PageUp) {
                                        viewLoader.pageUp();
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

                    // Message Text (if present)
                    Text {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        visible: root.messageText !== ""
                        text: root.messageText
                        font.family: Theme.glass.fontFamily
                        font.pixelSize: Theme.glass.fontSizeSmall
                        color: Theme.glass.textSecondary
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                        // Results View (Loader for List or Grid)
                        Loader {
                            id: viewLoader
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            
                            sourceComponent: root.viewMode === "grid" ? gridComponent : listComponent
                            
                            // Expose common interface for key navigation
                            property int count: item ? item.count : 0
                            property int currentIndex: item ? item.currentIndex : -1
                            
                            function increment() {
                                if (item) item.currentIndex = Math.min(item.currentIndex + 1, item.count - 1)
                            }
                            
                            function decrement() {
                                if (item) item.currentIndex = Math.max(item.currentIndex - 1, 0)
                            }
                            
                            function pageDown() {
                                if (item) item.currentIndex = Math.min(item.currentIndex + 5, item.count - 1)
                            }
                            
                            function pageUp() {
                                if (item) item.currentIndex = Math.max(item.currentIndex - 5, 0)
                            }
                            
                            function getCurrentItem() {
                                if (filteredModel.count > 0 && item && item.currentIndex >= 0) {
                                    return filteredModel.get(item.currentIndex)
                                }
                                return null
                            }
                        }

                        // --- List View Component ---
                        Component {
                            id: listComponent
                            ListView {
                                id: listView
                                spacing: 3
                                model: filteredModel

                                // Explicit property aliases for the Loader to access
                                property alias count: listView.count
                                property alias currentIndex: listView.currentIndex

                                // Delegate: Row item
                                delegate: Rectangle {
                                    id: delegateItem
                                    width: ListView.view.width
                                    height: 40
                                    radius: Theme.glass.cornerRadius - 6

                                    property bool isSelected: index === ListView.view.currentIndex
                                    property bool isHovered: delegateMouseArea.containsMouse

                                    // Glass button styling based on state
                                    color: {
                                        if (isSelected) return Qt.rgba(Theme.glass.accentColor.r, Theme.glass.accentColor.g, Theme.glass.accentColor.b, 0.32);
                                        if (isHovered) return Qt.rgba(1, 1, 1, 0.06);
                                        return Qt.rgba(1, 1, 1, 0.02);
                                    }

                                    border.color: (isSelected || isHovered) ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                                    border.width: (isSelected || isHovered) ? 1 : 0

                                    Behavior on color { ColorAnimation { duration: Theme.glass.animationDuration } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 10

                                        Text {
                                            visible: (model.iconPath || "") !== ""
                                            text: model.iconPath || ""
                                            font.family: Theme.glass.fontFamily
                                            font.pixelSize: 16
                                            color: delegateItem.isSelected ? Theme.glass.accentColorAlt : Theme.glass.textSecondary
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: model.displayText || ""
                                            font.family: Theme.glass.fontFamily
                                            font.pixelSize: Theme.glass.fontSizeMedium
                                            font.weight: delegateItem.isSelected ? Font.Medium : Font.Normal
                                            color: delegateItem.isSelected ? Theme.glass.textPrimary : Theme.glass.textSecondary
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: delegateMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: outputAndQuit(model.originalText || model.text);
                                    }
                                }
                                
                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                    width: 5
                                    contentItem: Rectangle { radius: 2.5; color: Qt.rgba(1, 1, 1, 0.25) }
                                }
                            }
                        }

                        // --- Grid View Component ---
                        Component {
                            id: gridComponent
                            GridView {
                                id: gridView
                                cellWidth: Math.floor(width / root.gridColumns)
                                cellHeight: cellWidth * 0.75 + 40
                                model: filteredModel
                                clip: true
                                cacheBuffer: 0
                                
                                // Explicit property aliases for the Loader to access
                                property alias count: gridView.count
                                property alias currentIndex: gridView.currentIndex
                                
                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                    width: 6
                                    contentItem: Rectangle { radius: 3; color: Qt.rgba(1, 1, 1, 0.3) }
                                }
                                
                                delegate: Item {
                                    id: gridDelegate
                                    width: gridView.cellWidth
                                    height: gridView.cellHeight
                                    
                                    property bool isSelected: GridView.isCurrentItem
                                    property bool isVisible: gridDelegate.y >= gridView.contentY - gridView.cellHeight &&
                                                            gridDelegate.y <= gridView.contentY + gridView.height + gridView.cellHeight
                                    
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 5
                                        radius: Theme.glass.cornerRadiusSmall
                                        color: (gridDelegate.isSelected || mouseArea.containsMouse) ? Qt.rgba(1,1,1,0.15) : Qt.rgba(1,1,1,0.05)
                                        border.color: gridDelegate.isSelected ? Theme.glass.accentColor : "transparent"
                                        border.width: gridDelegate.isSelected ? 2 : 0
                                        
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        
                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 6
                                            
                                            // Image container with fixed aspect ratio
                                            Rectangle {
                                                width: parent.width
                                                height: parent.height - labelText.height - parent.spacing
                                                color: Qt.rgba(0, 0, 0, 0.3)
                                                radius: 4
                                                clip: true
                                                
                                                // Only load image when delegate is visible (true lazy loading)
                                                Loader {
                                                    anchors.fill: parent
                                                    active: gridDelegate.isVisible
                                                    
                                                    sourceComponent: Image {
                                                        source: model.iconPath ? "file://" + model.iconPath : ""
                                                        asynchronous: true
                                                        cache: true
                                                        fillMode: Image.PreserveAspectCrop
                                                        smooth: true
                                                        mipmap: true // Use mipmaps for smoother downscaling
                                                        
                                                        // Important: Only load if source is valid, otherwise it might reload
                                                        // Using QQuickImage's native caching behavior
                                                        
                                                        // Placeholder while loading
                                                        Rectangle {
                                                            anchors.fill: parent
                                                            color: Qt.rgba(0.2, 0.2, 0.25, 1)
                                                            visible: parent.status !== Image.Ready
                                                            
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: parent.parent.status === Image.Loading ? "..." : "🖼"
                                                                font.pixelSize: 24
                                                                color: Theme.glass.textTertiary
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            
                                            // Label
                                            Text {
                                                id: labelText
                                                width: parent.width
                                                height: 28
                                                text: model.displayText || ""
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideMiddle
                                                maximumLineCount: 1
                                                color: Theme.glass.textPrimary
                                                font.family: Theme.glass.fontFamily
                                                font.pixelSize: Theme.glass.fontSizeSmall
                                            }
                                        }
                                        
                                        MouseArea {
                                            id: mouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                gridView.currentIndex = index
                                                outputAndQuit(model.originalText || model.text)
                                            }
                                        }
                                    }
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
     * We use a special prefix to distinguish real output from logs.
     */
    function outputAndQuit(text) {
        console.log("QS_DMENU_RESULT:" + text);
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
