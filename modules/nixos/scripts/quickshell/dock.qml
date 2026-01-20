import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Controls
import "./lib"

PanelWindow {
    id: dock
    
    // Dock at the bottom
    anchors {
        bottom: true
        left: true
        right: true
    }
    height: 64
    
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: 64
    
    color: "transparent"
    
    GlassPanel {
        anchors.fill: parent
        anchors.margins: 4
        cornerRadius: 16
        opacityValue: 0.6 // Slightly more opaque for the dock
        
        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8
            
            // --- Start Button ---
            GlassButton {
                implicitWidth: 48
                implicitHeight: 48
                text: "❄️" // NixOS Icon placeholder
                onClicked: {
                    // Launch the launcher
                    var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["qs", "-p", "' + Qt.resolvedUrl("../launcher.qml") + '"]; running: true }', dock)
                }
            }
            
            // --- Task List (Hyprland Clients) ---
            // Note: Quickshell.Hyprland usage depends on the specific version/API available.
            // Assuming standard Hyprland model binding or using a repeater with Hyprland global.
            
            Repeater {
                model: Hyprland.clients
                
                delegate: GlassButton {
                    implicitWidth: 48
                    implicitHeight: 48
                    text: model.class.substring(0, 2).toUpperCase() // Fallback icon
                    active: model.focus
                    
                    ToolTip.visible: hovered
                    ToolTip.text: model.title
                    
                    onClicked: {
                        model.focus = true
                    }
                }
            }
            
            Item { Layout.fillWidth: true } // Spacer
            
            // --- System Tray Area (Placeholder) ---
            GlassPanel {
                Layout.preferredHeight: 48
                Layout.preferredWidth: 150
                opacityValue: 0.3
                
                RowLayout {
                    anchors.centerIn: parent
                    Text {
                        text: Qt.formatTime(new Date(), "hh:mm")
                        color: Theme.foreground
                        font.family: Theme.fontName
                        font.bold: true
                    }
                }
            }
        }
    }
}
