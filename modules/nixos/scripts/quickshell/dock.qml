import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import "./lib"

PanelWindow {
    id: dock
    
    // Dock at the bottom centered
    anchors {
        bottom: true
        left: true
        right: true
    }
    
    // Fix: Use implicitHeight instead of height
    implicitHeight: 84
    
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusiveZone: 84
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    
    color: "transparent"
    
    // --- State Management ---
    
    property string configPath: Quickshell.env("HOME") + "/.config/quickshell/pinned.json"
    
    ListModel {
        id: pinnedAppsModel
    }

    // Hyprland Clients Model
    ListModel {
        id: runningAppsModel
    }

    // Poll for running clients
    Timer {
        interval: 1000 // Update every second
        running: true
        repeat: true
        onTriggered: {
            if (!fetchClients.running) fetchClients.running = true;
        }
    }

    // Initial fetch
    Component.onCompleted: {
        loadPinnedApps();
        if (!fetchClients.running) fetchClients.running = true;
    }

    Process {
        id: fetchClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientCollector
        }
        
        onExited: exitCode => {
            if (exitCode !== 0) return;
            
            try {
                var data = clientCollector.text;
                if (!data) return;
                
                var clients = JSON.parse(data);
                runningAppsModel.clear();
                
                // Sort by workspace
                clients.sort((a, b) => a.workspace.id - b.workspace.id);

                for (var i = 0; i < clients.length; i++) {
                    var c = clients[i];
                    if (c.class === "") continue;
                    
                    runningAppsModel.append({
                        address: c.address,
                        "class": c.class,
                        title: c.title,
                        icon: dock.resolveIcon(c.class)
                    });
                }
            } catch (e) {
                console.log("Error parsing clients: " + e.message);
            }
        }
    }

    // Fetch active window for focus indication
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            if (!fetchActive.running) fetchActive.running = true;
        }
    }
    
    property string activeWindowAddress: ""
    
    Process {
        id: fetchActive
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            id: activeCollector
        }
        
        onExited: exitCode => {
            if (exitCode !== 0) {
                 dock.activeWindowAddress = "";
                 return;
            }
            
            try {
                var data = activeCollector.text;
                if (!data) return;
                
                var win = JSON.parse(data);
                dock.activeWindowAddress = win.address;
            } catch (e) {
                dock.activeWindowAddress = "";
            }
        }
    }

    function savePinnedApps() {
        var apps = [];
        for (var i = 0; i < pinnedAppsModel.count; i++) {
            var item = pinnedAppsModel.get(i);
            apps.push({name: item.name, icon: item.icon, cmd: item.cmd});
        }
        var json = JSON.stringify(apps, null, 2);
        
        var proc = Qt.createQmlObject('import Quickshell.Io; Process { }', dock);
        var safeJson = json.replace(/'/g, "'\\''"); 
        proc.command = ["bash", "-c", "mkdir -p $(dirname '" + configPath + "') && echo '" + safeJson + "' > '" + configPath + "'"];
        proc.running = true;
    }

    function loadPinnedApps() {
        var proc = Qt.createQmlObject('import Quickshell.Io; Process { }', dock);
        proc.command = ["cat", configPath];
        
        var collector = Qt.createQmlObject('import Quickshell.Io; StdioCollector { }', proc);
        proc.stdout = collector;
        
        collector.onStreamFinished.connect(function() {
            try {
                if (collector.text.trim() === "") throw new Error("Empty file");
                var json = JSON.parse(collector.text);
                pinnedAppsModel.clear();
                for (var i = 0; i < json.length; i++) {
                    pinnedAppsModel.append(json[i]);
                }
            } catch (e) {
                console.log("Failed to load pinned apps (" + e.message + "), using defaults");
                loadDefaults();
            }
        });
        
        proc.onExited.connect(function(code) {
            if (code !== 0) loadDefaults();
        });
        
        proc.running = true;
    }

    function loadDefaults() {
        pinnedAppsModel.clear();
        pinnedAppsModel.append({ name: "Terminal", icon: "utilities-terminal", cmd: "kitty" });
        pinnedAppsModel.append({ name: "Browser", icon: "firefox", cmd: "firefox" });
        pinnedAppsModel.append({ name: "Files", icon: "system-file-manager", cmd: "nautilus" });
        savePinnedApps();
    }

    // Helper to resolve icons
    function resolveIcon(className) {
        if (!className) return "application-x-executable";
        var c = className.toLowerCase();
        if (c.includes("kitty")) return "utilities-terminal";
        if (c.includes("firefox")) return "firefox";
        if (c.includes("brave")) return "brave-browser";
        if (c.includes("chromium")) return "chromium";
        if (c.includes("chrome")) return "google-chrome";
        if (c.includes("discord")) return "discord";
        if (c.includes("code")) return "visual-studio-code";
        if (c.includes("neovim")) return "nvim";
        if (c.includes("obsidian")) return "obsidian";
        if (c.includes("spotify")) return "spotify";
        if (c.includes("nautilus") || c.includes("thunar") || c.includes("dolphin")) return "system-file-manager";
        if (c.includes("vlc")) return "vlc";
        if (c.includes("steam")) return "steam";
        return c;
    }

    // --- Context Menu ---
    
    Menu {
        id: contextMenu
        property var targetItem: null
        property bool isPinned: false
        property string appClass: ""
        property string appAddress: "" 
        
        background: Rectangle {
            implicitWidth: 200
            implicitHeight: 40
            color: Theme.glass.backgroundSolid
            border.color: Theme.glass.border
            radius: 8
        }
        
        MenuItem {
            text: contextMenu.isPinned ? "Unpin" : "Pin to Dock"
            onTriggered: {
                if (contextMenu.isPinned) {
                    for (var i = 0; i < pinnedAppsModel.count; i++) {
                        var item = pinnedAppsModel.get(i);
                        if (item.name === contextMenu.appClass) {
                            pinnedAppsModel.remove(i);
                            dock.savePinnedApps();
                            break;
                        }
                    }
                } else {
                    var name = contextMenu.appClass;
                    var icon = dock.resolveIcon(contextMenu.appClass);
                    var cmd = contextMenu.appClass.toLowerCase(); 
                    
                    var exists = false;
                    for (var j = 0; j < pinnedAppsModel.count; j++) {
                        if (pinnedAppsModel.get(j).name === name) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists) {
                        pinnedAppsModel.append({name: name, icon: icon, cmd: cmd});
                        dock.savePinnedApps();
                    }
                }
            }
        }
        
        MenuItem {
            text: "Close Window"
            visible: contextMenu.appAddress !== ""
            onTriggered: {
                var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["hyprctl", "dispatch", "closewindow", "address:" + parent.addr]; property string addr: ""; running: true }', dock)
                proc.addr = contextMenu.appAddress
            }
        }
    }

    // --- Main UI ---

    GlassPanel {
        id: dockContainer
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        
        width: dockLayout.implicitWidth + (Theme.glass.padding * 2)
        height: 68
        
        cornerRadius: 24
        
        // Use darker background with blue border as requested
        color: Qt.rgba(0.06, 0.06, 0.09, 0.85) 
        hasBorder: true
        
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
                
                // Fix: Use generic start icon if nix-snowflake is missing
                iconSource: "view-app-grid"
                text: "" 
                
                ToolTip.visible: hovered
                ToolTip.text: "Launchpad"
                ToolTip.delay: 500
                
                onClicked: {
                    var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["qs-launcher"]; running: true }', dock)
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
            
            // --- Pinned Apps ---
            Repeater {
                model: pinnedAppsModel
                
                delegate: GlassButton {
                    implicitWidth: 48
                    implicitHeight: 48
                    cornerRadius: 14
                    
                    iconSource: model.icon
                    
                    // Check if any running app matches this pinned app to show indicator
                    property bool isRunning: {
                        for (var i = 0; i < runningAppsModel.count; i++) {
                            // Rough match by name/class
                             if (dock.resolveIcon(runningAppsModel.get(i)["class"]) === model.icon) return true;
                        }
                        return false;
                    }
                    
                    active: isRunning
                    
                    onClicked: {
                         var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["' + model.cmd + '"]; running: true }', dock)
                    }
                    
                    onRightClicked: {
                        contextMenu.targetItem = model
                        contextMenu.isPinned = true
                        contextMenu.appClass = model.name
                        contextMenu.appAddress = ""
                        contextMenu.popup()
                    }
                    
                    ToolTip.visible: hovered
                    ToolTip.text: model.name
                    ToolTip.delay: 500
                    
                    // Dot indicator for running
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 4; height: 4; radius: 2
                        color: Theme.glass.accentColor
                        visible: isRunning
                    }
                }
            }
            
            // Separator
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 32
                color: Theme.glass.separator
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                visible: runningAppsModel.count > 0
            }
            
            // --- Running Apps (Hyprland) ---
            Repeater {
                model: runningAppsModel
                
                delegate: GlassButton {
                    // Hide if pinned? For now show duplicates as separate instances (Windows style)
                    // or implement filter. Let's show all for clarity.
                    
                    implicitWidth: 48
                    implicitHeight: 48
                    cornerRadius: 14
                    
                    iconSource: model.icon
                    
                    // Active window indicator
                    active: dock.activeWindowAddress === model.address
                    
                    onClicked: {
                         var proc = Qt.createQmlObject('import Quickshell.Io; Process { command: ["hyprctl", "dispatch", "focuswindow", "address:' + model.address + '"]; running: true }', dock)
                    }
                    
                    onRightClicked: {
                        contextMenu.targetItem = model
                        contextMenu.isPinned = false
                        contextMenu.appClass = model["class"]
                        contextMenu.appAddress = model.address
                        contextMenu.popup()
                    }
                    
                    ToolTip.visible: hovered
                    ToolTip.text: model.title
                    ToolTip.delay: 500
                    
                    // Active indicator (bar for focused)
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.active ? 20 : 4
                        height: 4; radius: 2
                        color: Theme.glass.accentColor
                        visible: true
                        
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                }
            }
        }
    }
}
