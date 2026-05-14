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
    readonly property string systemctlCommand: "__SYSTEMCTL__"
    readonly property string shellCommand: "__SH__"
    readonly property string wtypeCommand: "__WTYPE__"
    readonly property string wlCopyCommand: "__WL_COPY__"
    readonly property string notifySendCommand: "__NOTIFY_SEND__"
    readonly property string outputFile: "/tmp/voxtype-widget-transcript.txt"
    readonly property int refreshInterval: 750

    property string currentState: "stopped"
    property string previousState: "stopped"
    property string configSummary: "Loading configuration..."
    property string modelsSummary: "Loading models..."
    property string checkSummary: "Run a check to see setup status."
    property string lastTranscript: ""
    property string pendingRecordAction: ""
    property string activeRecordAction: ""
    property bool commandBusy: false
    property bool statusFailed: false
    property bool outputHandled: false
    property int transcriptReadAttempts: 0
    property bool autoType: false
    property bool autoCopy: true
    property bool autoNotify: false

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

    function recordCommand(action) {
        if (action === "start")
            return [root.shellCommand, "-c", "rm -f " + root.escapedPath(root.outputFile) + "; exec " + root.escapedPath(root.voxtypeCommand) + " record start --file=" + root.escapedPath(root.outputFile)]
        return commandLine(["record", action])
    }

    function refreshStatus() {
        if (!statusProcess.running)
            statusProcess.running = true
    }

    function runRecordCommand(action) {
        if (recordProcess.running || startDaemonProcess.running)
            return
        if (root.isStopped || root.statusFailed) {
            pendingRecordAction = action
            commandBusy = true
            startDaemonProcess.running = true
            return
        }
        commandBusy = true
        if (action === "start")
            outputHandled = false
        activeRecordAction = action
        recordProcess.command = recordCommand(action)
        recordProcess.running = true
    }

    function loadSettings() {
        if (!pluginService || !pluginService.loadPluginData)
            return
        autoType = pluginService.loadPluginData("voxtypeWidget", "autoType", false) === true
        autoCopy = pluginService.loadPluginData("voxtypeWidget", "autoCopy", true) !== false
        autoNotify = pluginService.loadPluginData("voxtypeWidget", "autoNotify", false) === true
    }

    function saveSetting(key, value) {
        if (pluginService && pluginService.savePluginData)
            pluginService.savePluginData("voxtypeWidget", key, value)
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

    function valueInSection(text, section, key) {
        const lines = (text || "").split("\n")
        let active = ""
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (line.length === 0)
                continue
            if (line[0] === "[") {
                active = line.replace("[", "").replace("]", "")
                continue
            }
            if (active === section && line.indexOf(key + " =") === 0)
                return line.substring(line.indexOf("=") + 1).trim()
        }
        return ""
    }

    function summarizeConfig(text) {
        const model = valueInSection(text, "whisper", "model")
        const engine = valueInSection(text, "engine", "engine")
        const output = valueInSection(text, "output", "mode")
        const stateFile = firstMatchingLine(text, ["(resolves to:"])
        const parts = []
        if (engine) parts.push("Engine: " + engine)
        if (model) parts.push("Model: " + model)
        if (output) parts.push("Output: " + output)
        if (stateFile) parts.push(stateFile.replace("(resolves to:", "State:").replace(")", ""))
        return parts.length ? parts.join("\n") : "No config details returned."
    }

    function escapedPath(path) {
        return "'" + String(path).replace(/'/g, "'\\''") + "'"
    }

    function processTranscript(text) {
        const clean = (text || "").trim()
        if (clean.length === 0)
            return
        outputHandled = true
        readTranscriptTimer.stop()
        lastTranscript = clean
        if (autoCopy)
            copyProcess.running = true
        if (autoType)
            typeProcess.running = true
        if (autoNotify)
            notifyProcess.running = true
    }

    function maybeReadTranscript() {
        if (!outputHandled && !readTranscriptProcess.running)
            readTranscriptProcess.running = true
    }

    function waitForTranscript() {
        transcriptReadAttempts = 0
        readTranscriptTimer.restart()
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
        loadSettings()
        refreshStatus()
        refreshDetails()
    }

    onPluginServiceChanged: loadSettings()

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
                    const oldState = root.currentState
                    root.previousState = root.currentState
                    root.currentState = state
                    root.statusFailed = false
                    if ((oldState === "transcribing" || oldState === "outputting") && state === "idle")
                        root.waitForTranscript()
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
            if (exitCode !== 0) {
                console.warn("VoxtypeWidget: record command failed", exitCode, recordStderr.text.trim())
            } else if (root.activeRecordAction === "stop") {
                root.waitForTranscript()
            }
            root.activeRecordAction = ""
            root.refreshStatus()
        }

        stderr: StdioCollector { id: recordStderr }
    }

    Process {
        id: startDaemonProcess
        command: [root.systemctlCommand, "--user", "start", "voxtype"]
        running: false

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.commandBusy = false
                root.pendingRecordAction = ""
                console.warn("VoxtypeWidget: failed to start voxtype service", exitCode, startDaemonStderr.text.trim())
                root.refreshStatus()
                return
            }
            root.refreshStatus()
            startAfterDaemonTimer.restart()
        }

        stderr: StdioCollector { id: startDaemonStderr }
    }

    Timer {
        id: startAfterDaemonTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (root.pendingRecordAction === "") {
                root.commandBusy = false
                return
            }
            if (root.pendingRecordAction === "start")
                root.outputHandled = false
            root.activeRecordAction = root.pendingRecordAction
            recordProcess.command = root.recordCommand(root.pendingRecordAction)
            root.pendingRecordAction = ""
            recordProcess.running = true
        }
    }

    Timer {
        id: readTranscriptTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.outputHandled || root.transcriptReadAttempts >= 90) {
                stop()
                return
            }
            root.transcriptReadAttempts += 1
            root.maybeReadTranscript()
        }
    }

    Process {
        id: readTranscriptProcess
        command: [root.shellCommand, "-c", "[ -s " + root.escapedPath(root.outputFile) + " ] && cat " + root.escapedPath(root.outputFile) + " || true"]
        running: false
        stdout: StdioCollector {
            id: transcriptCollector
            onStreamFinished: root.processTranscript(transcriptCollector.text)
        }
    }

    Process {
        id: copyProcess
        command: [root.shellCommand, "-c", root.wlCopyCommand + " < " + root.escapedPath(root.outputFile)]
        running: false
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("VoxtypeWidget: clipboard copy failed", exitCode)
        }
    }

    Process {
        id: typeProcess
        command: [root.shellCommand, "-c", root.wtypeCommand + " -- \"$(cat " + root.escapedPath(root.outputFile) + ")\""]
        running: false
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("VoxtypeWidget: auto type failed", exitCode)
        }
    }

    Process {
        id: notifyProcess
        command: [root.shellCommand, "-c", root.notifySendCommand + " 'Voxtype' \"$(cat " + root.escapedPath(root.outputFile) + ")\""]
        running: false
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("VoxtypeWidget: notification failed", exitCode)
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
                height: outputSettingsColumn.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Column {
                    id: outputSettingsColumn
                    width: parent.width - Theme.spacingM * 2
                    x: Theme.spacingM
                    y: Theme.spacingM
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Output"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    DankToggle {
                        width: parent.width
                        text: "Auto copy"
                        description: "Copy the transcription to the clipboard."
                        checked: root.autoCopy
                        onToggled: checked => {
                            root.autoCopy = checked
                            root.saveSetting("autoCopy", checked)
                        }
                    }

                    DankToggle {
                        width: parent.width
                        text: "Auto type"
                        description: "Type the transcription at the cursor."
                        checked: root.autoType
                        onToggled: checked => {
                            root.autoType = checked
                            root.saveSetting("autoType", checked)
                        }
                    }

                    DankToggle {
                        width: parent.width
                        text: "Notify result"
                        description: "Show a notification with the transcription."
                        checked: root.autoNotify
                        onToggled: checked => {
                            root.autoNotify = checked
                            root.saveSetting("autoNotify", checked)
                        }
                    }
                }
            }

            StyledRect {
                width: parent.width
                height: lastTranscriptColumn.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                visible: root.lastTranscript.length > 0

                Column {
                    id: lastTranscriptColumn
                    width: parent.width - Theme.spacingM * 2
                    x: Theme.spacingM
                    y: Theme.spacingM
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Last transcript"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: root.lastTranscript
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
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
