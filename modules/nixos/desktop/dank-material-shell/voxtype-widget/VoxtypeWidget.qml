import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property string voxtypeCommand: "__VOXTYPE__"
    readonly property int refreshInterval: 750

    property string currentState: "stopped"
    property string previousState: "stopped"
    property string configSummary: "Loading configuration..."
    property string modelsSummary: "Loading models..."
    property string checkSummary: "Run a check to see setup status."
    property bool commandBusy: false
    property bool statusFailed: false

    readonly property bool isReady: currentState === "idle"
    readonly property bool isRecording: currentState === "recording"
    readonly property bool isTranscribing: currentState === "transcribing"
    readonly property bool isStopped: currentState === "stopped"

    readonly property string stateIcon: statusFailed ? "mic_off" : (isRecording ? "fiber_manual_record" : (isTranscribing ? "hourglass_empty" : (isReady ? "mic" : "mic_off")))
    readonly property color stateColor: statusFailed ? Theme.error : (isRecording ? Theme.error : (isTranscribing ? Theme.warning : (isReady ? Theme.primary : Theme.surfaceVariantText)))
    readonly property string stateLabel: statusFailed ? "Unavailable" : (isRecording ? "Recording" : (isTranscribing ? "Transcribing" : (isReady ? "Ready" : "Stopped")))
    readonly property string stateHelp: statusFailed ? "Voxtype did not respond to the status command." : (isRecording ? "Click Stop to transcribe, or Cancel to discard." : (isTranscribing ? "Voxtype is turning audio into text." : (isReady ? "Ready to record and type at the cursor." : "Start the Voxtype daemon to enable voice typing.")))

    popoutWidth: 420

    function commandLine(args) {
        return [root.voxtypeCommand].concat(args || [])
    }

    function refreshStatus() {
        if (!statusProcess.running)
            statusProcess.running = true
    }

    function runRecordCommand(action) {
        if (recordProcess.running)
            return
        commandBusy = true
        recordProcess.command = commandLine(["record", action])
        recordProcess.running = true
    }

    function refreshDetails() {
        if (!configProcess.running)
            configProcess.running = true
        if (!modelsProcess.running)
            modelsProcess.running = true
    }

    function runSetupCheck() {
        if (checkProcess.running)
            return
        checkSummary = "Checking Voxtype setup..."
        checkProcess.running = true
    }

    function firstMatchingLine(text, prefixes) {
        const lines = (text || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            for (let j = 0; j < prefixes.length; j++) {
                if (line.indexOf(prefixes[j]) === 0)
                    return line
            }
        }
        return ""
    }

    function summarizeConfig(text) {
        const model = firstMatchingLine(text, ["model ="])
        const engine = firstMatchingLine(text, ["engine ="])
        const output = firstMatchingLine(text, ["mode ="])
        const stateFile = firstMatchingLine(text, ["(resolves to:"])
        const parts = []
        if (engine) parts.push(engine.replace("engine =", "Engine:"))
        if (model) parts.push(model.replace("model =", "Model:"))
        if (output) parts.push(output.replace("mode =", "Output:"))
        if (stateFile) parts.push(stateFile.replace("(resolves to:", "State:").replace(")", ""))
        return parts.length ? parts.join("\n") : "No config details returned."
    }

    function summarizeModels(text) {
        const clean = (text || "").trim()
        return clean.length ? clean : "No downloaded models found yet."
    }

    function summarizeCheck(text) {
        const lines = (text || "").split("\n")
        const interesting = []
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].replace(/\u001b\[[0-9;]*m/g, "").trim()
            if (line.indexOf("✓") >= 0 || line.indexOf("✗") >= 0 || line.indexOf("⚠") >= 0)
                interesting.push(line)
        }
        return interesting.length ? interesting.slice(0, 8).join("\n") : "Setup check completed."
    }

    Component.onCompleted: {
        refreshStatus()
        refreshDetails()
    }

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refreshDetails()
    }

    Process {
        id: statusProcess
        command: root.commandLine(["status"])
        running: false

        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: {
                const state = statusCollector.text.trim()
                if (state.length > 0) {
                    root.previousState = root.currentState
                    root.currentState = state
                    root.statusFailed = false
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                root.statusFailed = true
        }
    }

    Process {
        id: recordProcess
        running: false
        onExited: exitCode => {
            root.commandBusy = false
            if (exitCode !== 0)
                console.warn("VoxtypeWidget: record command failed", exitCode)
            root.refreshStatus()
        }
    }

    Process {
        id: configProcess
        command: root.commandLine(["config"])
        running: false
        stdout: StdioCollector {
            id: configCollector
            onStreamFinished: root.configSummary = root.summarizeConfig(configCollector.text)
        }
    }

    Process {
        id: modelsProcess
        command: root.commandLine(["setup", "model", "--list"])
        running: false
        stdout: StdioCollector {
            id: modelsCollector
            onStreamFinished: root.modelsSummary = root.summarizeModels(modelsCollector.text)
        }
    }

    Process {
        id: checkProcess
        command: root.commandLine(["setup", "check"])
        running: false
        stdout: StdioCollector {
            id: checkStdout
            onStreamFinished: root.checkSummary = root.summarizeCheck(checkStdout.text + "\n" + checkStderr.text)
        }
        stderr: StdioCollector { id: checkStderr }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: row.implicitWidth
            implicitHeight: root.widgetThickness

            Row {
                id: row
                spacing: Theme.spacingXS
                anchors.centerIn: parent

                DankIcon {
                    name: root.stateIcon
                    size: Theme.barIconSize(root.barThickness, -4)
                    color: root.stateColor
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation on opacity {
                        running: root.isRecording
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.45; duration: 500; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
                    }
                }

                StyledText {
                    text: root.stateLabel
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.stateColor
                    visible: root.barConfig?.maximizeWidgetText ?? false
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: root.widgetThickness
            implicitHeight: icon.height

            DankIcon {
                id: icon
                name: root.stateIcon
                size: Theme.barIconSize(root.barThickness)
                color: root.stateColor
                anchors.centerIn: parent
            }
        }
    }

    popoutContent: Component {
        Column {
            spacing: Theme.spacingM
            implicitHeight: childrenRect.height

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                DankIcon {
                    name: root.stateIcon
                    size: Theme.iconSizeLarge
                    color: root.stateColor
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: "Voxtype " + root.stateLabel
                        font.pixelSize: Theme.fontSizeXLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: root.stateHelp
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                DankActionButton {
                    buttonSize: 32
                    iconName: "refresh"
                    iconColor: Theme.surfaceVariantText
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        root.refreshStatus()
                        root.refreshDetails()
                    }
                }
            }

            RowLayout {
                width: parent.width
                spacing: Theme.spacingS

                DankButton {
                    text: root.isRecording ? "Stop" : "Record"
                    iconName: root.isRecording ? "stop" : "mic"
                    backgroundColor: root.isRecording ? Theme.error : Theme.primary
                    textColor: root.isRecording ? Theme.errorText : Theme.primaryText
                    enabled: !root.commandBusy && !root.isTranscribing
                    Layout.fillWidth: true
                    onClicked: root.runRecordCommand(root.isRecording ? "stop" : "start")
                }

                DankButton {
                    text: "Cancel"
                    iconName: "close"
                    backgroundColor: Theme.surfaceContainerHigh
                    textColor: Theme.surfaceText
                    enabled: !root.commandBusy && (root.isRecording || root.isTranscribing)
                    Layout.fillWidth: true
                    onClicked: root.runRecordCommand("cancel")
                }
            }

            StyledRect {
                width: parent.width
                height: configColumn.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: configColumn
                    width: parent.width - Theme.spacingM * 2
                    x: Theme.spacingM
                    y: Theme.spacingM
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Configuration"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: root.configSummary
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
            }

            StyledRect {
                width: parent.width
                height: modelsColumn.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: modelsColumn
                    width: parent.width - Theme.spacingM * 2
                    x: Theme.spacingM
                    y: Theme.spacingM
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Models"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: root.modelsSummary
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
            }

            StyledRect {
                width: parent.width
                height: checkColumn.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: checkColumn
                    width: parent.width - Theme.spacingM * 2
                    x: Theme.spacingM
                    y: Theme.spacingM
                    spacing: Theme.spacingS

                    RowLayout {
                        width: parent.width

                        StyledText {
                            text: "Setup check"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            Layout.fillWidth: true
                        }

                        DankActionButton {
                            buttonSize: 28
                            iconName: checkProcess.running ? "hourglass_empty" : "play_arrow"
                            iconColor: Theme.surfaceVariantText
                            enabled: !checkProcess.running
                            onClicked: root.runSetupCheck()
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: root.checkSummary
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
