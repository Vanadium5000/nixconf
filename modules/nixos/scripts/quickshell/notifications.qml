/*
 * notifications.qml - Quickshell Notification Center Entry Point
 *
 * Main entry point for the notification daemon and center.
 * Registers the NotificationServer and creates popup/panel windows.
 */

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import "./lib"
import "./notifications"

ShellRoot {
    id: root

    // Sound player (in main file so it works properly)
    MediaPlayer {
        id: dingPlayer
        source: "file:///run/current-system/sw/share/sounds/freedesktop/stereo/message.oga"
        audioOutput: AudioOutput {
            volume: NotificationCenter.soundVolume
        }
    }

    Connections {
        target: NotificationCenter
        function onPlayDingSignal() {
            dingPlayer.play()
        }
    }

    // Popup notifications (corner popups)
    NotificationPopup {
        notificationService: NotificationCenter
    }

    // Full notification panel
    NotificationPanel {
        notificationService: NotificationCenter
    }
}
