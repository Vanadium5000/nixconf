import QtQuick
import Quickshell.Io

Item {
    id: root
    
    // Unique name for the lock (e.g. "launcher", "dock", "dmenu")
    required property string lockName
    
    // Path to the lock file
    readonly property string pidFile: "/dev/shm/qs_" + lockName + ".pid"
    
    // If true, we just kill the old one and exit (toggle behavior) if the old one was us?
    // Actually, for a "Launcher", usually:
    // - If running: Close it.
    // - If not running: Open it.
    // But Quickshell is the process. If we kill the old one, we are the NEW one.
    // So we effectively replace it.
    // To support "Toggle" (Open -> Close), the *trigger* (keybind) usually handles logic?
    // No, if the keybind just runs `qs-launcher`:
    //   1. First run: Starts.
    //   2. Second run: Detects old one, kills it. Then... WE should exit too?
    //      If we replace it, we just restart the launcher (resetting state).
    //      If we want to toggle (close), we should detect "Old one was alive, so I killed it, and now I die too".
    
    property bool toggle: Quickshell.env("QS_TOGGLE") === "true"

    Component.onCompleted: {
        lockManager.running = true
    }

    Process {
        id: lockManager
        command: ["bash", "-c", "
            PIDFILE='" + root.pidFile + "'
            ME=$$
            
            if [ -f \"$PIDFILE\" ]; then
                OLD_PID=$(cat \"$PIDFILE\")
                if kill -0 \"$OLD_PID\" 2>/dev/null; then
                    # Old instance is running
                    if [ \"" + root.toggle + "\" = \"true\" ]; then
                        # Toggle mode: Kill old, and we exit (toggle off)
                        kill \"$OLD_PID\"
                        echo \"TOGGLED_OFF\"
                        exit 0
                    else
                        # Replace mode: Kill old, we take over
                        kill \"$OLD_PID\"
                    fi
                fi
            fi
            
            # Write our parent PID (the quickshell process) to lockfile
            echo $PPID > \"$PIDFILE\"
            echo \"ACQUIRED\"
        "]
        
        stdout: SplitParser {
            onRead: (data) => {
                if (data.trim() === "TOGGLED_OFF") {
                    console.log("[InstanceLock] Toggled off previous instance. Exiting.")
                    Qt.quit()
                } else if (data.trim() === "ACQUIRED") {
                    console.log("[InstanceLock] Acquired lock for " + root.lockName)
                }
            }
        }
    }

    Component.onDestruction: {
        cleanup.running = true
    }

    Process {
        id: cleanup
        command: ["rm", "-f", root.pidFile]
    }
}
