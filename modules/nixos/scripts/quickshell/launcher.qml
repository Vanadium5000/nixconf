import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import Quickshell 1.0
import Quickshell.Io 1.0
import Quickshell.Wayland 1.0
import "./lib" 1.0

Scope {
    id: root
    
    property string mode: Quickshell.env("LAUNCHER_MODE") ?? "app" // app, calc
    
    // --- Window Configuration ---
    // Floating centered window for the launcher
    PanelWindow {
        id: window
        anchors.centerIn: parent
        width: 600
        height: root.mode === "calc" ? 200 : 500
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
                                    var proc = Qt.createQmlObject('import Quickshell.Io 1.0; Process { command: ["wl-copy", "' + calcResult.text + '"]; running: true }', root)
                                    Qt.quit()
                                }
                            } else {
                                if (appModel.count > 0) {
                                    runner.command = [appModel.get(0).exec]
                                    runner.running = true
                                    Qt.quit()
                                }
                            }
                        }
                        
                        onTextChanged: {
                            if (root.mode === "app") {
                                appSearcher.running = true
                            } else if (root.mode === "calc") {
                                calcRunner.running = true
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
                    visible: root.mode === "app"
                    id: appView

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    
                    model: ListModel { id: appModel }
                    
                    delegate: GlassButton {
                        width: appView.width
                        height: 50
                        text: model.name
                        icon: "" // TODO: Icon support
                        active: index === 0 // Highlight first match
                        
                        onClicked: {
                            runner.command = [model.exec]
                            runner.running = true
                            Qt.quit()
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
        // Find .desktop files, grep Name and Exec, format as JSON-ish lines
        // Note: This is a rough approximation. A proper implementation needs a dedicated helper.
        command: ["bash", "-c", "grep -rPh '^Name=|^Exec=' /run/current-system/sw/share/applications | paste - - | grep -i '" + searchInput.text + "' | head -n 10"]
        
        stdout: StdioCollector {
            onStreamFinished: {
                appModel.clear()
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim()
                    if (!line) continue
                    
                    // Expecting: Name=Firefox\tExec=firefox %u
                    var parts = line.split("\t")
                    if (parts.length >= 2) {
                        var name = parts[0].replace("Name=", "")
                        var exec = parts[1].replace("Exec=", "").replace(/%[fFuU]/, "").trim()
                        
                        appModel.append({ "name": name, "exec": exec })
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
                calcResult.text = text.trim()
            }
        }
    }

    Process {
        id: runner
        running: false
        onExited: Qt.quit()
    }
}
