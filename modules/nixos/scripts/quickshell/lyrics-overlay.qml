/*
 * lyrics-overlay.qml - Synced Lyrics Display
 *
 * Floating overlay that displays synchronized lyrics from a data source.
 * Typically driven by 'synced-lyrics' or compatible MPRIS wrappers.
 *
 * Features:
 * - Karaoke-style line highlighting
 * - Upcoming lines preview
 * - Click-through normal mode
 * - Temporary in-memory edit mode for placement and sizing
 */

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
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
    // Read from environment variables with sensible defaults.
    readonly property int defaultNumLines: parseInt(Quickshell.env("LYRICS_LINES") ?? "0")
    property int numLines: root.clamp(root.defaultNumLines, 0, 4)
    property string positionMode: Quickshell.env("LYRICS_POSITION") ?? "bottom"
    property bool editMode: false
    readonly property int defaultFontSize: parseInt(Quickshell.env("LYRICS_FONT_SIZE") ?? Theme.fontSizeLarge.toString())
    readonly property real defaultBackgroundOpacity: parseFloat(Quickshell.env("LYRICS_BACKGROUND_OPACITY") ?? "0.12")
    property int fontSize: root.defaultFontSize
    property string textColor: Quickshell.env("LYRICS_COLOR") ?? Theme.foreground
    property real textOpacity: parseFloat(Quickshell.env("LYRICS_OPACITY") ?? "0.82")
    property real backgroundOpacity: root.defaultBackgroundOpacity
    property string fontFamily: Quickshell.env("LYRICS_FONT") ?? Theme.fontName
    property bool showShadow: (Quickshell.env("LYRICS_SHADOW") ?? "true") === "true"
    property int lineSpacing: parseInt(Quickshell.env("LYRICS_SPACING") ?? "4")
    property int maxLineLength: parseInt(Quickshell.env("LYRICS_LENGTH") ?? "0")
    property int cardInset: 16
    property int cardRadius: 14
    property int cardPadding: 8
    property int railHeight: 24
    property int controlGap: 4
    property int controlButtonSize: 24
    readonly property int controlPanelPadding: 6
    readonly property int controlPanelWidth: 336
    readonly property int controlPanelHeight: root.controlButtonSize + root.controlPanelPadding * 2
    readonly property int controlPanelX: root.clamp(root.cardX + Math.round((root.cardWidth - root.controlPanelWidth) / 2), 4, Math.max(4, root.screenWidth() - root.controlPanelWidth - 4))
    readonly property int controlPanelY: root.cardY >= root.controlPanelHeight + 8 ? root.cardY - root.controlPanelHeight - 6 : root.clamp(root.cardY + root.cardHeight + 6, 4, Math.max(4, root.screenHeight() - root.controlPanelHeight - 4))
    readonly property int osdWidth: Math.min(520, Math.max(220, root.screenWidth() - 32))
    readonly property int osdHeight: 46
    readonly property int osdX: root.clamp(root.cardX + Math.round((root.cardWidth - root.osdWidth) / 2), 4, Math.max(4, root.screenWidth() - root.osdWidth - 4))
    readonly property int osdY: root.controlPanelY >= root.osdHeight + 8 ? root.controlPanelY - root.osdHeight - 6 : root.clamp(root.controlPanelY + root.controlPanelHeight + 6, 4, Math.max(4, root.screenHeight() - root.osdHeight - 4))
    property int resizeGripSize: 16
    property int normalDragHandleWidth: 36
    property int normalDragHandleHeight: 10
    property int editResizeHitSize: 52 // Bigger hit area makes corner resizing easier without a larger visible grip.
    property int minCardWidth: 48
    property int minCardHeight: 24
    property int cardWidth: parseInt(Quickshell.env("LYRICS_CARD_WIDTH") ?? "360")
    property int cardHeight: parseInt(Quickshell.env("LYRICS_CARD_HEIGHT") ?? "92")
    property int cardX: 0
    property int cardY: 0
    property bool geometryInitialized: false
    property bool moveDragActive: false
    property bool resizeDragActive: false
    property real dragPressX: 0
    property real dragPressY: 0
    property int dragStartX: 0
    property int dragStartY: 0
    property int dragStartWidth: 0
    property int dragStartHeight: 0
    readonly property int maxCardWidth: Math.max(root.minCardWidth, root.screenWidth() - root.cardInset * 2)
    readonly property int maxCardHeight: Math.max(root.minCardHeight, root.screenHeight() - root.cardInset * 2)
    readonly property int availableLyricsHeight: Math.max(1, root.cardHeight - root.cardPadding * 2)
    property int previousLineCount: parseInt(Quickshell.env("LYRICS_PREVIOUS_LINES") ?? "0")
    property int futureLineCount: root.numLines === 0 ? 3 : root.clamp(root.numLines - 1, 0, 3)
    readonly property int requestedLineCount: root.clamp(root.previousLineCount + 1 + root.futureLineCount, 1, 12)
    readonly property int visibleLineCount: root.maxVisibleLinesForHeight()
    readonly property real adaptiveLineHeight: Math.max(1, (root.availableLyricsHeight - Math.max(0, root.visibleLineCount - 1) * root.effectiveLineSpacing()) / root.visibleLineCount)
    readonly property int adaptiveCurrentFontSize: root.clamp(Math.round(Math.min(root.fontSize * 0.82, root.adaptiveLineHeight * 0.78, (root.cardWidth - root.cardPadding * 2) / 4.5)), 5, root.fontSize)
    readonly property int adaptiveUpcomingFontSize: root.clamp(Math.round(Math.min(root.fontSize * 0.56, root.adaptiveLineHeight * 0.66, (root.cardWidth - root.cardPadding * 2) / 5.0)), 4, Math.max(4, root.fontSize))

    // --- State ---
    property string currentLine: ""
    property var upcomingLines: []
    property var displayLines: []
    property string trackInfo: ""
    property bool isPlaying: false
    property string osdText: ""
    property bool osdVisible: false
    property int nextChangeInMs: 400

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function beginMoveDrag(source, mouse) {
        var point = source.mapToItem(stage, mouse.x, mouse.y);
        root.moveDragActive = true;
        root.dragPressX = point.x;
        root.dragPressY = point.y;
        root.dragStartX = root.cardX;
        root.dragStartY = root.cardY;
    }

    function updateMoveDrag(source, mouse) {
        if (!root.moveDragActive) {
            return;
        }

        var point = source.mapToItem(stage, mouse.x, mouse.y);
        root.cardX = root.clamp(root.dragStartX + Math.round(point.x - root.dragPressX), 0, Math.max(0, stage.width - root.cardWidth));
        root.cardY = root.clamp(root.dragStartY + Math.round(point.y - root.dragPressY), 0, Math.max(0, stage.height - root.cardHeight));
    }

    function endMoveDrag() {
        root.moveDragActive = false;
    }

    function beginResizeDrag(source, mouse) {
        var point = source.mapToItem(stage, mouse.x, mouse.y);
        root.resizeDragActive = true;
        root.dragPressX = point.x;
        root.dragPressY = point.y;
        root.dragStartWidth = root.cardWidth;
        root.dragStartHeight = root.cardHeight;
    }

    function updateResizeDrag(source, mouse) {
        if (!root.resizeDragActive) {
            return;
        }

        var point = source.mapToItem(stage, mouse.x, mouse.y);
        root.cardWidth = root.clamp(root.dragStartWidth + Math.round(point.x - root.dragPressX), root.effectiveMinCardWidth(), Math.max(root.effectiveMinCardWidth(), stage.width - root.cardX));
        root.cardHeight = root.clamp(root.dragStartHeight + Math.round(point.y - root.dragPressY), root.effectiveMinCardHeight(), Math.max(root.effectiveMinCardHeight(), stage.height - root.cardY));
    }

    function endResizeDrag() {
        root.resizeDragActive = false;
    }

    function adjustFontSize(delta) {
        root.fontSize = root.clamp(root.fontSize + delta, 6, 72);
        root.showValueOsd("Font " + root.fontSize + "px" + (root.fontSize === root.defaultFontSize ? " (Default)" : ""));
    }

    function adjustBackgroundOpacity(delta) {
        root.backgroundOpacity = root.clamp(root.backgroundOpacity + delta, 0.02, 0.72);
        root.showValueOsd("Background " + Math.round(root.backgroundOpacity * 100) + "%" + (Math.abs(root.backgroundOpacity - root.defaultBackgroundOpacity) < 0.005 ? " (Default)" : ""));
    }

    function adjustLineCount(delta) {
        root.futureLineCount = root.clamp(root.futureLineCount + delta, 0, 10);
        root.showValueOsd("Future lyrics " + root.futureLineCount);
    }

    function adjustPreviousLineCount(delta) {
        root.previousLineCount = root.clamp(root.previousLineCount + delta, 0, 10);
        root.showValueOsd("Previous lyrics " + root.previousLineCount);
    }

    function showValueOsd(text) {
        root.osdText = text;
        root.osdVisible = true;
        osdTimer.restart();
    }

    function showEditHelp() {
        root.showValueOsd("✓ done · ▶ play/pause · -/+A font · -/+P previous lines · -/+F future lines · -/+◼ background · × close");
    }

    function scheduleLyricsUpdate(delayMs) {
        updateTimer.stop();
        updateTimer.interval = root.clamp(Math.round(delayMs), 16, 1000);
        updateTimer.start();
    }

    function handleEditAction(action) {
        if (action === "done")
            root.setEditMode(false);
        else if (action === "play")
            playerctlProcess.running = true;
        else if (action === "close")
            Qt.quit();
        else if (action === "fontDown")
            root.adjustFontSize(-2);
        else if (action === "fontUp")
            root.adjustFontSize(2);
        else if (action === "prevDown")
            root.adjustPreviousLineCount(-1);
        else if (action === "prevUp")
            root.adjustPreviousLineCount(1);
        else if (action === "bgDown")
            root.adjustBackgroundOpacity(-0.05);
        else if (action === "bgUp")
            root.adjustBackgroundOpacity(0.05);
        else if (action === "linesDown")
            root.adjustLineCount(-1);
        else if (action === "linesUp")
            root.adjustLineCount(1);
    }

    function screenWidth() {
        return screen ? screen.width : 1280;
    }

    function screenHeight() {
        return screen ? screen.height : 720;
    }

    function effectiveMinCardWidth() {
        return Math.max(1, Math.min(root.minCardWidth, root.screenWidth()));
    }

    function effectiveMinCardHeight() {
        return Math.max(1, Math.min(root.minCardHeight, root.screenHeight()));
    }

    function effectiveLineSpacing() {
        return root.clamp(root.lineSpacing, 0, Math.max(0, Math.round(root.cardHeight / 16)));
    }

    function desiredLineHeight(index) {
        var currentIndex = root.previousLineCount;
        var size = index === currentIndex ? root.fontSize * 0.82 : root.fontSize * 0.56;
        return Math.max(6, Math.ceil(size * 1.18));
    }

    function maxVisibleLinesForHeight() {
        var used = 0;
        var spacing = root.effectiveLineSpacing();
        var fit = 1;

        for (var i = 0; i < root.requestedLineCount; i++) {
            var next = used + (i > 0 ? spacing : 0) + root.desiredLineHeight(i);
            if (i > 0 && next > root.availableLyricsHeight) {
                break;
            }
            used = next;
            fit = i + 1;
        }

        return Math.max(1, fit);
    }

    function defaultCardWidth() {
        return root.clamp(parseInt(Quickshell.env("LYRICS_CARD_WIDTH") ?? "360"), root.effectiveMinCardWidth(), root.maxCardWidth);
    }

    function defaultCardHeight() {
        return root.clamp(parseInt(Quickshell.env("LYRICS_CARD_HEIGHT") ?? "92"), root.effectiveMinCardHeight(), root.maxCardHeight);
    }

    function defaultCardX() {
        var maxX = Math.max(0, root.screenWidth() - root.cardWidth);
        var centered = Math.round((root.screenWidth() - root.cardWidth) / 2);
        return root.clamp(centered, 0, maxX);
    }

    function defaultCardY() {
        var maxY = Math.max(0, root.screenHeight() - root.cardHeight);

        if (root.positionMode === "top") {
            return root.clamp(root.cardInset, 0, maxY);
        }

        if (root.positionMode === "center") {
            return root.clamp(Math.round((root.screenHeight() - root.cardHeight) / 2), 0, maxY);
        }

        return root.clamp(root.screenHeight() - root.cardHeight - root.cardInset, 0, maxY);
    }

    function initializeGeometry() {
        if (root.geometryInitialized) {
            return;
        }

        root.cardWidth = root.defaultCardWidth();
        root.cardHeight = root.defaultCardHeight();
        root.cardX = root.defaultCardX();
        root.cardY = root.defaultCardY();
        root.geometryInitialized = true;
    }

    function setEditMode(enabled) {
        root.editMode = enabled;
        if (enabled)
            root.showEditHelp();
    }

    // --- Window Layout ---
    // Keep the layer surface full-screen so the visible card can move without
    // reconfiguring the window itself.
    implicitWidth: root.screenWidth()
    implicitHeight: root.screenHeight()
    color: "transparent"

    // Keep the overlay decorative only; it should not reserve space or grab focus.
    exclusiveZone: -1
    exclusionMode: ExclusionMode.Ignore

    // Compose the mask from explicit controls so normal mode only intercepts the
    // drag handle and edit pill. Active drags temporarily widen the mask so fast
    // pointer motion keeps delivering events per the
    // Quickshell QsWindow.mask docs: https://quickshell.org/docs/master/types/Quickshell/QsWindow#mask
    mask: Region {
        Region {
            item: (root.moveDragActive || root.resizeDragActive) ? stage : (root.editMode ? surface : normalDragHandle)
        }

        Region {
            item: (root.editMode || root.moveDragActive || root.resizeDragActive) ? null : editButton
        }

        Region {
            item: root.editMode ? editControlPanel : null
        }

        Region {
            item: root.osdVisible ? valueOsd : null
        }
    }

    anchors.left: true
    anchors.top: true
    anchors.right: true
    anchors.bottom: true

    Item {
        id: stage
        anchors.fill: parent

        Item {
            id: surface
            x: root.cardX
            y: root.cardY
            width: root.cardWidth
            height: root.cardHeight

            Rectangle {
                id: cardBackground
                anchors.fill: parent
                radius: root.cardRadius
                color: Theme.rgba(Theme.glass.backgroundColor, root.editMode ? root.clamp(root.backgroundOpacity + 0.18, 0.08, 0.82) : root.backgroundOpacity)
                border.width: root.editMode ? 1 : 0
                border.color: Theme.rgba(root.textColor, 0.16)
                clip: true
            }

            MouseArea {
                id: editMoveArea
                z: 2
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.SizeAllCursor
                preventStealing: true
                visible: root.editMode
                enabled: root.editMode

                onPressed: function (mouse) {
                    root.beginMoveDrag(editMoveArea, mouse);
                }
                onPositionChanged: function (mouse) {
                    root.updateMoveDrag(editMoveArea, mouse);
                }
                onReleased: root.endMoveDrag()
                onCanceled: root.endMoveDrag()
            }

            Item {
                id: editButton
                z: 20
                visible: !root.editMode
                width: 28
                height: 28
                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.right: parent.right
                anchors.rightMargin: 4
                opacity: editButtonHover.containsMouse ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    radius: 10
                    color: Theme.rgba(Theme.foreground, 0.14)
                }

                Text {
                    anchors.centerIn: parent
                    text: "✎"
                    color: root.textColor
                    opacity: 0.78
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: editButtonHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setEditMode(true)
                }
            }

            Item {
                id: normalDragHandle
                visible: !root.editMode
                z: 18
                width: root.normalDragHandleWidth
                height: root.normalDragHandleHeight
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8

                MouseArea {
                    id: normalDragArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.SizeAllCursor
                    preventStealing: true
                    visible: !root.editMode
                    enabled: !root.editMode

                    onPressed: function (mouse) {
                        root.beginMoveDrag(normalDragArea, mouse);
                    }
                    onPositionChanged: function (mouse) {
                        root.updateMoveDrag(normalDragArea, mouse);
                    }
                    onReleased: root.endMoveDrag()
                    onCanceled: root.endMoveDrag()
                }
            }

            Item {
                id: body
                z: 3
                anchors {
                    fill: parent
                    margins: root.cardPadding
                }
                clip: true

                Item {
                    id: editHeader
                    width: parent.width
                    height: 0
                    visible: false
                }

                Column {
                    id: lyricsColumn
                    width: parent.width
                    anchors.top: editHeader.bottom
                    anchors.topMargin: 0
                    spacing: root.effectiveLineSpacing()

                    Repeater {
                        model: root.displayLines.length > 0 ? root.displayLines : [
                            {
                                text: root.currentLine || "♪",
                                current: true
                            }
                        ]

                        delegate: Text {
                            required property int index
                            required property var modelData

                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData.text || ""
                            color: root.textColor
                            opacity: modelData.current ? (root.currentLine ? root.textOpacity : 0.5) : Math.max(0.22, root.textOpacity * (0.56 - Math.abs(index - root.currentDisplayIndex()) * 0.08))
                            font.family: root.fontFamily
                            font.pixelSize: modelData.current ? root.adaptiveCurrentFontSize : root.adaptiveUpcomingFontSize
                            font.weight: modelData.current ? Font.Medium : Font.Normal
                            style: root.showShadow ? Text.Outline : Text.Normal
                            styleColor: modelData.current ? "#80000000" : "#60000000"
                            maximumLineCount: 1
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                    }
                }
                Item {
                    id: resizeHitArea
                    z: 50
                    visible: root.editMode
                    width: root.editResizeHitSize
                    height: root.editResizeHitSize
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    Rectangle {
                        id: resizeGrip
                        width: root.resizeGripSize
                        height: root.resizeGripSize
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        color: Theme.rgba(Theme.foreground, 0.10)
                        radius: 8

                        Text {
                            anchors.centerIn: parent
                            text: "[]"
                            color: root.textColor
                            opacity: 0.9
                            font.family: root.fontFamily
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: resizeDragArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.SizeFDiagCursor
                        preventStealing: true
                        visible: root.editMode
                        enabled: root.editMode

                        onPressed: function (mouse) {
                            root.beginResizeDrag(resizeDragArea, mouse);
                        }
                        onPositionChanged: function (mouse) {
                            root.updateResizeDrag(resizeDragArea, mouse);
                        }
                        onReleased: root.endResizeDrag()
                        onCanceled: root.endResizeDrag()
                    }
                }
            }
        }

        Rectangle {
            id: editControlPanel
            z: 60
            visible: root.editMode
            x: root.controlPanelX
            y: root.controlPanelY
            width: root.controlPanelWidth
            height: root.controlPanelHeight
            radius: Math.round(height / 2)
            color: Theme.rgba(Theme.glass.backgroundColor, 0.36)
            border.width: 1
            border.color: Theme.rgba(root.textColor, 0.12)
            opacity: root.editMode ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: root.controlGap

                Repeater {
                    model: [
                        {
                            icon: "✓",
                            action: "done"
                        },
                        {
                            icon: root.isPlaying ? "⏸" : "▶",
                            action: "play"
                        },
                        {
                            icon: "−A",
                            action: "fontDown"
                        },
                        {
                            icon: "+A",
                            action: "fontUp"
                        },
                        {
                            icon: "−P",
                            action: "prevDown"
                        },
                        {
                            icon: "+P",
                            action: "prevUp"
                        },
                        {
                            icon: "−F",
                            action: "linesDown"
                        },
                        {
                            icon: "+F",
                            action: "linesUp"
                        },
                        {
                            icon: "−◼",
                            action: "bgDown"
                        },
                        {
                            icon: "+◼",
                            action: "bgUp"
                        },
                        {
                            icon: "×",
                            action: "close"
                        }
                    ]

                    delegate: Rectangle {
                        required property var modelData

                        width: root.controlButtonSize
                        height: root.controlButtonSize
                        radius: Math.round(root.controlButtonSize / 2)
                        color: editControlMouse.containsMouse ? Theme.rgba(Theme.foreground, 0.24) : Theme.rgba(Theme.foreground, 0.10)

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.icon
                            color: root.textColor
                            opacity: 0.92
                            font.family: root.fontFamily
                            font.pixelSize: parent.modelData.icon.length > 1 ? 9 : 13
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: editControlMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.handleEditAction(parent.modelData.action)
                        }
                    }
                }
            }
        }

        Rectangle {
            id: valueOsd
            z: 70
            visible: root.osdVisible
            x: root.osdX
            y: root.osdY
            width: root.osdWidth
            height: root.osdHeight
            radius: Math.round(height / 2)
            color: Theme.rgba(Theme.glass.backgroundColor, 0.46)
            border.width: 1
            border.color: Theme.rgba(root.textColor, 0.12)
            opacity: root.osdVisible ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 16
                text: root.osdText
                color: root.textColor
                opacity: 0.95
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    Timer {
        id: osdTimer
        interval: 3500
        repeat: false
        onTriggered: root.osdVisible = false
    }

    Process {
        id: playerctlProcess
        command: ["playerctl", "play-pause"]
        running: false
    }

    // Process to fetch lyrics data.
    Process {
        id: lyricsProcess
        command: Quickshell.env("OVERLAY_COMMAND") ? Quickshell.env("OVERLAY_COMMAND").split(" ") : ["lyricsctl", "current", "--json", "--lines", root.visibleLineCount.toString(), "--length", root.maxLineLength.toString()]
        running: false

        stdout: StdioCollector {
            id: stdoutCollector
            onStreamFinished: {
                root.parseLyricsOutput(stdoutCollector.text);
                root.scheduleLyricsUpdate(root.nextChangeInMs);
            }
        }

        onExited: function (exitCode) {
            // If the process exits without streamFinished, still schedule the next update.
            if (exitCode !== 0) {
                root.scheduleLyricsUpdate(400);
            }
        }
    }

    function parseLyricsOutput(output) {
        try {
            var data = JSON.parse(output.trim());
            root.currentLine = data.text || data.current || "";
            root.isPlaying = data.alt === "playing";

            if (data.timedLines && data.timedLines.length > 0) {
                var sourceLines = data.allTimedLines && data.allTimedLines.length > 0 ? data.allTimedLines : data.timedLines;
                root.displayLines = root.selectDisplayLines(sourceLines);
            } else if (data.upcoming) {
                root.upcomingLines = data.upcoming.slice(0, root.visibleLineCount - 1);
                root.displayLines = [
                    {
                        text: root.currentLine || "♪",
                        current: true
                    }
                ].concat(root.upcomingLines.map(line => ({
                            text: line,
                            current: false
                        })));
            } else if (data.lines && data.lines.length > 1) {
                root.upcomingLines = data.lines.slice(1, root.visibleLineCount);
                root.displayLines = data.lines.slice(0, root.visibleLineCount).map((line, index) => ({
                            text: line,
                            current: index === 0
                        }));
            } else if (data.tooltip) {
                // Parse tooltip for older compatible producers.
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
                root.upcomingLines = upcoming.slice(0, root.visibleLineCount - 1);
                root.displayLines = [
                    {
                        text: root.currentLine || "♪",
                        current: true
                    }
                ].concat(root.upcomingLines.map(line => ({
                            text: line,
                            current: false
                        })));
            } else {
                root.displayLines = [
                    {
                        text: root.currentLine || "♪",
                        current: true
                    }
                ];
            }
            var elapsed = data.generatedAtMs ? Math.max(0, Date.now() - data.generatedAtMs) : 0;
            root.nextChangeInMs = data.nextChangeInMs ? root.clamp(data.nextChangeInMs - elapsed + 24, 80, 200) : 200;
        } catch (e) {
            console.log("Parse error:", e);
            root.nextChangeInMs = 400;
        }
    }

    function currentDisplayIndex() {
        for (var i = 0; i < root.displayLines.length; i++) {
            if (root.displayLines[i].current)
                return i;
        }
        return 0;
    }

    function selectDisplayLines(lines) {
        var currentIndex = -1;
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].current) {
                currentIndex = i;
                root.currentLine = lines[i].text || root.currentLine;
                break;
            }
        }

        if (currentIndex < 0) {
            return lines.slice(0, root.visibleLineCount).map(line => ({
                        text: line.text || "",
                        current: false
                    }));
        }

        var start = root.clamp(currentIndex - root.previousLineCount, 0, Math.max(0, lines.length - 1));
        var end = root.clamp(currentIndex + root.futureLineCount + 1, currentIndex + 1, lines.length);
        return lines.slice(start, end).map(line => ({
                    text: line.text || "",
                    current: line.current === true
                }));
    }

    // Timer for periodic updates.
    Timer {
        id: updateTimer
        interval: parseInt(Quickshell.env("LYRICS_UPDATE_INTERVAL") ?? "200")
        repeat: false
        onTriggered: {
            lyricsProcess.running = true;
        }
    }

    // Start fetching on load.
    Component.onCompleted: {
        root.initializeGeometry();
        lyricsProcess.running = true;
    }
}
