/*
 * dock.qml - Desktop Dock
 *
 * Bottom edge panel with pinned apps and running tasks.
 * Features:
 * - Smart hide/show on hover
 * - Pinned apps management (json persistence)
 * - Hyprland taskbar integration
 * - Single instance locking
 */

//@ pragma IconTheme Papirus

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
    
    InstanceLock {
        lockName: "dock"
        toggle: false // Dock should replace old instance, not toggle close
    }
    
    // --- Window Configuration ---

    // Positioning
    // Top, Bottom, Left, Right
    property string position: "bottom" // Default
    
    // Overlay Mode: If true, renders on Overlay layer (over fullscreens). 
    // If false, renders on Top layer (reserves space)
    property bool overlayMode: false 
    
    anchors {
        bottom: position === "bottom"
        top: position === "top"
        left: position === "left" || position === "top" || position === "bottom"
        right: position === "right" || position === "top" || position === "bottom"
    }
    
    // Dimensions
    implicitHeight: (position === "bottom" || position === "top") ? 84 : 0
    implicitWidth: (position === "left" || position === "right") ? 84 : 0
    
    // Layer Configuration
    // User requested: "stop off-setting/reserving space from the windows by default"
    // So default exclusiveZone should be -1 (no reservation), unless explicitly enabled.
    property bool reserveSpace: false // Default to false
    
    // Logic: Only reserve if enabled AND not hidden AND not overlay mode
    property bool effectiveReserve: reserveSpace && !overlayMode && !dockState.hidden
    
    WlrLayershell.layer: overlayMode ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.exclusiveZone: effectiveReserve ? 84 : -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    
    color: "transparent"
    
    // --- Smart Hide Logic ---
    
    property bool smartHide: false // Default to false (always visible)
    property bool isHovered: mouseArea.containsMouse
    property bool forceShow: false // Controlled by signal or external
    
    // Hide Timer
    Timer {
        id: hideTimer
        interval: 3000
        running: dock.smartHide && !dock.isHovered && !dock.forceShow
        repeat: false
        onTriggered: {
            // Trigger hide animation state
            dockState.hidden = true
        }
    }
    
    // Reset timer on hover
    onIsHoveredChanged: {
        if (isHovered) {
            dockState.hidden = false
            hideTimer.stop()
        } else {
            hideTimer.restart()
        }
    }
    
    // State Tracker
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
                        icon: c.class.toLowerCase()
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
        pinnedAppsModel.append({ name: "Terminal", icon: "terminal", cmd: "kitty" });
        pinnedAppsModel.append({ name: "Browser", icon: "firefox", cmd: "firefox" });
        pinnedAppsModel.append({ name: "Files", icon: "system-file-manager", cmd: "nautilus" });
        savePinnedApps();
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
        
        delegate: MenuItem {
            id: menuItem
            contentItem: Text {
                text: menuItem.text
                font.family: Theme.glass.fontFamily
                font.pixelSize: Theme.glass.fontSizeMedium
                color: Theme.glass.textPrimary
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                implicitWidth: 200
                implicitHeight: 36
                color: menuItem.highlighted ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                radius: 4
            }
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
                    var icon = contextMenu.appClass.toLowerCase();
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
        
        // Animation for Smart Hide
        // We animate the vertical offset (translation)
        transform: Translate {
            y: dockState.hidden ? (dock.position === "bottom" ? 100 : 0) : 0
            x: dockState.hidden ? (dock.position === "left" ? -100 : (dock.position === "right" ? 100 : 0)) : 0
            
            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
        }
        
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dockState.hidden ? -60 : 8 // Tuck away partially or fully
        anchors.horizontalCenter: parent.horizontalCenter
        
        // Auto-width based on content
        width: dockLayout.implicitWidth + (Theme.glass.padding * 2)
        height: 68
        
        cornerRadius: 24
        
        // Use darker background with blue border as requested
        color: Qt.rgba(0.06, 0.06, 0.09, 0.85) 
        hasBorder: true
        
        // Hovering the dock container keeps it awake
        HoverHandler {
            onHoveredChanged: if (hovered) dockState.hidden = false
        }
        
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
                             if (runningAppsModel.get(i)["class"].toLowerCase() === model.icon) return true;
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
