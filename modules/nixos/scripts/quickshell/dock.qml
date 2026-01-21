import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "./lib"

PanelWindow {
    id: dock
    
    // Dock at the bottom centered
    anchors {
        bottom: true
    }
    width: dockLayout.implicitWidth + 20
    height: 84 // Enough for 64px icons + padding + bounce
    
    // Center horizontally using screen info if available, otherwise rely on compositor placement 
    // or use anchors.horizontalCenter if Quickshell supports it for PanelWindow (it might not).
    // For now, we set left/right to undefined and let Hyprland center it via exclusive zone or similar?
    // Actually, Quickshell PanelWindow usually anchors to edges. 
    // To center a floating dock, we might need a full width window with centered content
    // OR rely on the compositor to center the surface if we don't anchor left/right.
    // Let's use full width transparent window for safety, but limit hit area if possible.
    // However, for a dock we usually want full width for edge triggers.
    // Let's stick to full width but centered visual panel.
    
    anchors.left: true
    anchors.right: true
    
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: 84
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    
    color: "transparent"
    
    // Mouse hover detection for the whole bottom area to potentially show dock if hidden (future feature)
    
    // The visual dock container
    GlassPanel {
        id: dockContainer
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        
        width: dockLayout.implicitWidth + (Theme.glass.padding * 2)
        height: 68
        
        cornerRadius: 24
        
        // MacOS style dock background
        color: Qt.rgba(
            Theme.glass.backgroundColor.r,
            Theme.glass.backgroundColor.g,
            Theme.glass.backgroundColor.b,
            0.5 // More translucent
        )
        
        // Content
        RowLayout {
            id: dockLayout
            anchors.centerIn: parent
            spacing: 8
            
            // --- Launcher ---
            GlassButton {
                implicitWidth: 48
                implicitHeight: 48
                cornerRadius: 14
                
                text: "🚀" // Grid icon
                
                // Active indicator (Launcher is technically always "ready")
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -4
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 4; height: 4; radius: 2
                    color: Theme.glass.textTertiary
                    visible: false
                }
                
                onClicked: {
                    var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["qs-launcher"]; running: true }', dock)
                }
                
                ToolTip.visible: hovered
                ToolTip.text: "Launchpad"
            }
            
            // Separator
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 32
                color: Theme.glass.separator
                Layout.leftMargin: 4
                Layout.rightMargin: 4
            }
            
            // --- Pinned Apps (Hardcoded for now) ---
            
            Repeater {
                model: ListModel {
                    ListElement { name: "Terminal"; icon: "💻"; cmd: "kitty" }
                    ListElement { name: "Browser"; icon: "🌐"; cmd: "firefox" }
                    ListElement { name: "Files"; icon: "📁"; cmd: "nautilus" }
                }
                
                delegate: GlassButton {
                    implicitWidth: 48
                    implicitHeight: 48
                    cornerRadius: 14
                    text: model.icon
                    
                    onClicked: {
                         var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["' + model.cmd + '"]; running: true }', dock)
                    }
                    
                    ToolTip.visible: hovered
                    ToolTip.text: model.name
                    
                    // Check if running (naive check - would need process matching or Hyprland matching)
                    // For now, static.
                }
            }
            
            // Separator
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 32
                color: Theme.glass.separator
                Layout.leftMargin: 4
                Layout.rightMargin: 4
            }
            
            // --- Running Apps (Hyprland) ---
            Repeater {
                model: Hyprland.clients
                
                delegate: GlassButton {
                    implicitWidth: 48
                    implicitHeight: 48
                    cornerRadius: 14
                    
                    // Icon logic: Try to map class to icon, fallback to text
                    text: {
                        var c = model.class.toLowerCase();
                        if (c.includes("kitty") || c.includes("term")) return "💻";
                        if (c.includes("firefox") || c.includes("brave") || c.includes("chrome")) return "🌐";
                        if (c.includes("discord")) return "💬";
                        if (c.includes("code") || c.includes("neovim")) return "📝";
                        if (c.includes("obsidian")) return "📓";
                        if (c.includes("spotify")) return "🎵";
                        return model.class.substring(0, 1).toUpperCase();
                    }
                    
                    active: model.focus
                    
                    // Running Indicator
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 4; height: 4; radius: 2
                        color: Theme.glass.accentColor
                        visible: true
                    }
                    
                    onClicked: {
                        model.focus = true
                    }
                    
                    ToolTip.visible: hovered
                    ToolTip.text: model.title
                }
            }
            
            // Spacer if empty
            Item {
                visible: Hyprland.clients.count === 0
                width: 1
                height: 1
            }
        }
    }
}
