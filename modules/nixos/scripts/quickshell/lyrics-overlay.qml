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
    property int numLines: parseInt(Quickshell.env("LYRICS_LINES") ?? "3")
    property string positionMode: Quickshell.env("LYRICS_POSITION") ?? "bottom"
    property bool editMode: false
    property int fontSize: parseInt(Quickshell.env("LYRICS_FONT_SIZE") ?? Theme.fontSizeLarge.toString())
    property string textColor: Quickshell.env("LYRICS_COLOR") ?? Theme.foreground
    property real textOpacity: parseFloat(Quickshell.env("LYRICS_OPACITY") ?? "0.95")
    property string fontFamily: Quickshell.env("LYRICS_FONT") ?? Theme.fontName
    property bool showShadow: (Quickshell.env("LYRICS_SHADOW") ?? "true") === "true"
    property int lineSpacing: parseInt(Quickshell.env("LYRICS_SPACING") ?? "8")
    property int maxLineLength: parseInt(Quickshell.env("LYRICS_LENGTH") ?? "0")
    property int cardInset: 24
    property int cardRadius: 20
    property int cardPadding: 14
    property int railHeight: 28
    property int controlGap: 8
    property int controlHeight: 20
    property int resizeGripSize: 18
    property int normalDragHandleWidth: 44
    property int normalDragHandleHeight: 14
    property int editResizeHitSize: 52 // Bigger hit area makes corner resizing easier without a larger visible grip.
    property int minCardWidth: 320
    property int minCardHeight: 136
    property int cardWidth: parseInt(Quickshell.env("LYRICS_CARD_WIDTH") ?? "520")
    property int cardHeight: parseInt(Quickshell.env("LYRICS_CARD_HEIGHT") ?? "188")
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

    // --- State ---
    property string currentLine: ""
    property var upcomingLines: []
    property string trackInfo: ""
    property bool isPlaying: false

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value))
    }

    function beginMoveDrag(source, mouse) {
        var point = source.mapToItem(stage, mouse.x, mouse.y)
        root.moveDragActive = true
        root.dragPressX = point.x
        root.dragPressY = point.y
        root.dragStartX = root.cardX
        root.dragStartY = root.cardY
    }

    function updateMoveDrag(source, mouse) {
        if (!root.moveDragActive) {
            return
        }

        var point = source.mapToItem(stage, mouse.x, mouse.y)
        root.cardX = root.clamp(root.dragStartX + Math.round(point.x - root.dragPressX), 0, Math.max(0, stage.width - root.cardWidth))
        root.cardY = root.clamp(root.dragStartY + Math.round(point.y - root.dragPressY), 0, Math.max(0, stage.height - root.cardHeight))
    }

    function endMoveDrag() {
        root.moveDragActive = false
    }

    function beginResizeDrag(source, mouse) {
        var point = source.mapToItem(stage, mouse.x, mouse.y)
        root.resizeDragActive = true
        root.dragPressX = point.x
        root.dragPressY = point.y
        root.dragStartWidth = root.cardWidth
        root.dragStartHeight = root.cardHeight
    }

    function updateResizeDrag(source, mouse) {
        if (!root.resizeDragActive) {
            return
        }

        var point = source.mapToItem(stage, mouse.x, mouse.y)
        root.cardWidth = root.clamp(root.dragStartWidth + Math.round(point.x - root.dragPressX), root.effectiveMinCardWidth(), Math.max(root.effectiveMinCardWidth(), stage.width - root.cardX))
        root.cardHeight = root.clamp(root.dragStartHeight + Math.round(point.y - root.dragPressY), root.effectiveMinCardHeight(), Math.max(root.effectiveMinCardHeight(), stage.height - root.cardY))
    }

    function endResizeDrag() {
        root.resizeDragActive = false
    }

    function screenWidth() {
        return screen ? screen.width : 1280
    }

    function screenHeight() {
        return screen ? screen.height : 720
    }

    function effectiveMinCardWidth() {
        return Math.max(1, Math.min(root.minCardWidth, root.screenWidth()))
    }

    function effectiveMinCardHeight() {
        return Math.max(1, Math.min(root.minCardHeight, root.screenHeight()))
    }

    function defaultCardWidth() {
        return root.clamp(parseInt(Quickshell.env("LYRICS_CARD_WIDTH") ?? "520"), root.effectiveMinCardWidth(), root.maxCardWidth)
    }

    function defaultCardHeight() {
        return root.clamp(parseInt(Quickshell.env("LYRICS_CARD_HEIGHT") ?? "188"), root.effectiveMinCardHeight(), root.maxCardHeight)
    }

    function defaultCardX() {
        var maxX = Math.max(0, root.screenWidth() - root.cardWidth)
        var centered = Math.round((root.screenWidth() - root.cardWidth) / 2)
        return root.clamp(centered, 0, maxX)
    }

    function defaultCardY() {
        var maxY = Math.max(0, root.screenHeight() - root.cardHeight)

        if (root.positionMode === "top") {
            return root.clamp(root.cardInset, 0, maxY)
        }

        if (root.positionMode === "center") {
            return root.clamp(Math.round((root.screenHeight() - root.cardHeight) / 2), 0, maxY)
        }

        return root.clamp(root.screenHeight() - root.cardHeight - root.cardInset, 0, maxY)
    }

    function initializeGeometry() {
        if (root.geometryInitialized) {
            return
        }

        root.cardWidth = root.defaultCardWidth()
        root.cardHeight = root.defaultCardHeight()
        root.cardX = root.defaultCardX()
        root.cardY = root.defaultCardY()
        root.geometryInitialized = true
    }

    function setEditMode(enabled) {
        root.editMode = enabled
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
                color: Theme.rgba(Theme.glass.backgroundColor, root.editMode ? 0.82 : 0.66)
                clip: true
            }

            Rectangle {
                id: editButton
                z: 20
                visible: !root.editMode
                width: 30
                height: 24
                radius: 12
                anchors.top: parent.top
                anchors.topMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 8
                color: Theme.rgba(Theme.foreground, 0.16)

                Text {
                    anchors.centerIn: parent
                    text: "edit"
                    color: root.textColor
                    opacity: 0.9
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Medium
                }

                MouseArea {
                    anchors.fill: parent
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

                Rectangle {
                    anchors.centerIn: parent
                    width: 32
                    height: 4
                    radius: 2
                    color: Theme.rgba(root.textColor, 0.22)
                }

                MouseArea {
                    id: normalDragArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.SizeAllCursor
                    preventStealing: true
                    visible: !root.editMode
                    enabled: !root.editMode

                    onPressed: function (mouse) { root.beginMoveDrag(normalDragArea, mouse) }
                    onPositionChanged: function (mouse) { root.updateMoveDrag(normalDragArea, mouse) }
                    onReleased: root.endMoveDrag()
                    onCanceled: root.endMoveDrag()
                }
            }

            Item {
                id: body
                anchors {
                    fill: parent
                    margins: root.cardPadding
                }
                clip: true

                Item {
                    id: editHeader
                    width: parent.width
                    height: root.editMode ? root.railHeight : 0
                    visible: root.editMode

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Theme.rgba(Theme.glass.accentColor, 0.08)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 4
                    radius: 2
                    color: Theme.rgba(root.textColor, 0.24)
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 48
                    anchors.verticalCenter: parent.verticalCenter
                    text: "edit mode"
                    color: root.textColor
                    opacity: 0.78
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }

                Row {
                    z: 1
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.controlGap

                    Rectangle {
                        width: 48
                        height: root.controlHeight
                        radius: 10
                        color: Theme.rgba(Theme.foreground, 0.10)

                        Text {
                            anchors.centerIn: parent
                            text: "done"
                            color: root.textColor
                            opacity: 0.9
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setEditMode(false)
                        }
                    }

                    Rectangle {
                        width: 74
                        height: root.controlHeight
                        radius: 10
                        color: Theme.rgba(Theme.foreground, 0.10)

                        Text {
                            anchors.centerIn: parent
                            text: "play/pause"
                            color: root.textColor
                            opacity: 0.9
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: playerctlProcess.running = true
                        }
                    }

                    Rectangle {
                        width: 48
                        height: root.controlHeight
                        radius: 10
                        color: Theme.rgba(Theme.foreground, 0.10)

                        Text {
                            anchors.centerIn: parent
                            text: "close"
                            color: root.textColor
                            opacity: 0.9
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.quit()
                        }
                    }
                }

                        MouseArea {
                            id: editHeaderDragArea
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.SizeAllCursor
                            preventStealing: true
                            visible: root.editMode
                            enabled: root.editMode
                            z: 0

                            onPressed: function (mouse) { root.beginMoveDrag(editHeaderDragArea, mouse) }
                            onPositionChanged: function (mouse) { root.updateMoveDrag(editHeaderDragArea, mouse) }
                            onReleased: root.endMoveDrag()
                            onCanceled: root.endMoveDrag()
                        }
                }

                Column {
                    id: lyricsColumn
                    width: parent.width
                    anchors.top: editHeader.bottom
                    anchors.topMargin: root.editMode ? 10 : 0
                    spacing: Math.max(4, root.lineSpacing - 2)

                Text {
                    id: currentText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.currentLine || "♪"
                    color: root.textColor
                    opacity: root.currentLine ? root.textOpacity : 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(22, Math.round(root.fontSize * 0.88))
                    font.weight: Font.Medium
                    style: root.showShadow ? Text.Outline : Text.Normal
                    styleColor: "#80000000"
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone

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
                        opacity: Math.max(0.22, root.textOpacity * (0.56 - index * 0.12))
                        font.family: root.fontFamily
                        font.pixelSize: Math.max(15, Math.round(root.fontSize * 0.68))
                        font.weight: Font.Normal
                        style: root.showShadow ? Text.Outline : Text.Normal
                        styleColor: "#60000000"
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                }

                }
                Item {
                    id: resizeHitArea
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

                        onPressed: function (mouse) { root.beginResizeDrag(resizeDragArea, mouse) }
                        onPositionChanged: function (mouse) { root.updateResizeDrag(resizeDragArea, mouse) }
                        onReleased: root.endResizeDrag()
                        onCanceled: root.endResizeDrag()
                    }
                }
            }
        }
    }

    Process {
        id: playerctlProcess
        command: ["playerctl", "play-pause"]
        running: false
    }

    // Process to fetch lyrics data.
    Process {
        id: lyricsProcess
        command: Quickshell.env("OVERLAY_COMMAND")
            ? Quickshell.env("OVERLAY_COMMAND").split(" ")
            : ["synced-lyrics", "current", "--json", "--lines", root.numLines.toString(), "--length", root.maxLineLength.toString()]
        running: false

        stdout: StdioCollector {
            id: stdoutCollector
            onStreamFinished: {
                root.parseLyricsOutput(stdoutCollector.text)
                // Schedule next update.
                updateTimer.start()
            }
        }

        onExited: function (exitCode) {
            // If the process exits without streamFinished, still schedule the next update.
            if (exitCode !== 0) {
                updateTimer.start()
            }
        }
    }

    function parseLyricsOutput(output) {
        try {
            var data = JSON.parse(output.trim())
            if (data.text) {
                root.currentLine = data.text
            }
            root.isPlaying = data.alt === "playing"

            // Parse tooltip for upcoming lines.
            if (data.tooltip) {
                var lines = data.tooltip.split("\n")
                var upcoming = []
                var foundCurrent = false

                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i]
                    if (line.startsWith("►") || line.startsWith("<b>►")) {
                        foundCurrent = true
                        continue
                    }
                    if (foundCurrent && line.trim() && !line.startsWith("<")) {
                        upcoming.push(line.trim())
                    }
                }
                root.upcomingLines = upcoming.slice(0, root.numLines - 1)
            }
        } catch (e) {
            console.log("Parse error:", e)
        }
    }

    // Timer for periodic updates.
    Timer {
        id: updateTimer
        interval: parseInt(Quickshell.env("LYRICS_UPDATE_INTERVAL") ?? "400")
        repeat: false
        onTriggered: {
            lyricsProcess.running = true
        }
    }

    // Start fetching on load.
    Component.onCompleted: {
        root.initializeGeometry()
        lyricsProcess.running = true
    }
}
