/*
 * notifications.qml - Quickshell Notification Center Entry Point
 *
 * Main entry point for the notification daemon and center.
 * Registers the NotificationServer and creates popup/panel windows.
 */

import QtQuick
import Quickshell
import Quickshell.Wayland
import "./lib"

ShellRoot {
    id: root

    // The notification service singleton
    NotificationCenter {
        id: notificationService
    }

    // Popup notifications (corner popups)
    NotificationPopup {
        notificationService: notificationService
    }

    // Full notification panel
    NotificationPanel {
        notificationService: notificationService
    }
}
