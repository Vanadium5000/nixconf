/*
 * notification-center.qml - Liquid Glass Notification Center
 *
 * A full-featured notification daemon and center implementing the Liquid Glass
 * design language. Replaces swaync with native Quickshell implementation.
 *
 * Features:
 * - Popup notifications with configurable timeout
 * - Expandable notification center panel
 * - Notification actions (buttons)
 * - App icon rendering
 * - Copy body to clipboard
 * - Notification grouping by app
 * - Persistent storage across restarts
 * - Ding sound support with per-app settings
 * - Do Not Disturb mode
 */

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import Qt5Compat.GraphicalEffects
import "./lib"

Singleton {
    id: root

    // =========================================================================
    // Public Properties
    // =========================================================================

    property list<NotificationWrapper> notifications: []
    readonly property list<NotificationWrapper> popups: notifications.filter(n => n.isPopup)
    readonly property int count: notifications.length
    readonly property int unreadCount: notifications.filter(n => !n.read).length

    property bool dndEnabled: false
    property bool panelVisible: false
    property real soundVolume: 0.5

    // Ding sound settings per urgency level
    property var dingSoundSettings: ({
        "low": false,
        "normal": true,
        "critical": true
    })

    // Per-app ding overrides (appName -> bool)
    property var appDingOverrides: ({})

    // =========================================================================
    // Signals
    // =========================================================================

    signal notificationReceived(var notification)
    signal notificationDismissed(int id)
    signal panelToggled(bool visible)

    // =========================================================================
    // Public Functions
    // =========================================================================

    function togglePanel() {
        panelVisible = !panelVisible
        panelToggled(panelVisible)
        if (panelVisible) {
            markAllAsRead()
        }
    }

    function showPanel() {
        panelVisible = true
        panelToggled(true)
        markAllAsRead()
    }

    function hidePanel() {
        panelVisible = false
        panelToggled(false)
    }

    function dismissNotification(id: int) {
        const index = notifications.findIndex(n => n.id === id)
        if (index !== -1) {
            const notif = notifications[index]
            if (notif.notification) {
                notif.notification.dismiss()
            }
            notifications.splice(index, 1)
            notifications = notifications.slice() // Trigger update
            notificationDismissed(id)
            saveNotifications()
        }
    }

    function dismissAll() {
        notifications.forEach(n => {
            if (n.notification) {
                n.notification.dismiss()
            }
        })
        notifications = []
        saveNotifications()
    }

    function markAllAsRead() {
        notifications.forEach(n => n.read = true)
        notifications = notifications.slice()
    }

    function invokeAction(notifId: int, actionIdentifier: string) {
        const notif = notifications.find(n => n.id === notifId)
        if (notif && notif.notification) {
            const action = notif.notification.actions.find(a => a.identifier === actionIdentifier)
            if (action) {
                action.invoke()
            }
        }
        dismissNotification(notifId)
    }

    function copyToClipboard(text: string) {
        Quickshell.clipboardText = text
    }

    function setDingForApp(appName: string, enabled: bool) {
        appDingOverrides[appName] = enabled
        appDingOverrides = Object.assign({}, appDingOverrides)
        saveSettings()
    }

    function setDingForUrgency(urgency: string, enabled: bool) {
        dingSoundSettings[urgency] = enabled
        dingSoundSettings = Object.assign({}, dingSoundSettings)
        saveSettings()
    }

    function toggleDnd() {
        dndEnabled = !dndEnabled
        saveSettings()
    }

    // =========================================================================
    // Notification Wrapper Component
    // =========================================================================

    component NotificationWrapper: QtObject {
        id: wrapper

        required property int id
        property Notification notification
        property bool isPopup: false
        property bool read: false
        property date time: new Date()

        // Cached properties for persistence
        property string summary: notification?.summary ?? ""
        property string body: notification?.body ?? ""
        property string appName: notification?.appName ?? ""
        property string appIcon: notification?.appIcon ?? ""
        property string image: notification?.image ?? ""
        property int urgency: notification?.urgency ?? NotificationUrgency.Normal
        property list<var> actions: notification?.actions.map(a => ({
            identifier: a.identifier,
            text: a.text
        })) ?? []

        readonly property string urgencyString: {
            switch (urgency) {
                case NotificationUrgency.Low: return "low"
                case NotificationUrgency.Critical: return "critical"
                default: return "normal"
            }
        }

        readonly property string timeAgo: {
            const now = new Date()
            const diff = Math.floor((now - time) / 1000)
            if (diff < 60) return "now"
            if (diff < 3600) return Math.floor(diff / 60) + "m"
            if (diff < 86400) return Math.floor(diff / 3600) + "h"
            return Math.floor(diff / 86400) + "d"
        }

        property Timer popupTimer: Timer {
            interval: 7000
            running: wrapper.isPopup
            onTriggered: {
                wrapper.isPopup = false
                root.notifications = root.notifications.slice()
            }
        }

        onNotificationChanged: {
            if (notification) {
                summary = notification.summary
                body = notification.body
                appName = notification.appName
                appIcon = notification.appIcon
                image = notification.image
                urgency = notification.urgency
                actions = notification.actions.map(a => ({
                    identifier: a.identifier,
                    text: a.text
                }))
            }
        }
    }

    Component {
        id: notificationWrapperComponent
        NotificationWrapper {}
    }

    // =========================================================================
    // Notification Server
    // =========================================================================

    property int idOffset: 0

    NotificationServer {
        id: notificationServer

        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        persistenceSupported: true
        keepOnReload: false

        onNotification: (notification) => {
            notification.tracked = true

            const newId = notification.id + root.idOffset
            const wrapper = notificationWrapperComponent.createObject(root, {
                id: newId,
                notification: notification,
                isPopup: !root.dndEnabled && !root.panelVisible,
                time: new Date()
            })

            root.notifications = [wrapper, ...root.notifications]
            root.notificationReceived(wrapper)

            // Play ding sound if enabled
            root.maybePlayDing(wrapper)

            root.saveNotifications()
        }
    }

    // =========================================================================
    // Sound System
    // =========================================================================

    MediaPlayer {
        id: dingPlayer
        source: "file:///run/current-system/sw/share/sounds/freedesktop/stereo/message.oga"
        audioOutput: AudioOutput {
            volume: root.soundVolume
        }
    }

    function maybePlayDing(notif: NotificationWrapper) {
        if (root.dndEnabled) return

        // Check app-specific override first
        if (notif.appName in root.appDingOverrides) {
            if (root.appDingOverrides[notif.appName]) {
                dingPlayer.play()
            }
            return
        }

        // Fall back to urgency-based setting
        if (root.dingSoundSettings[notif.urgencyString]) {
            dingPlayer.play()
        }
    }

    function playDing() {
        dingPlayer.play()
    }

    // =========================================================================
    // Persistence
    // =========================================================================

    property string dataDir: Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
    property string notifStoragePath: dataDir + "/quickshell/notifications.json"
    property string settingsPath: dataDir + "/quickshell/notification-settings.json"

    function saveNotifications() {
        const data = notifications.map(n => ({
            id: n.id,
            summary: n.summary,
            body: n.body,
            appName: n.appName,
            appIcon: n.appIcon,
            image: n.image,
            urgency: n.urgency,
            time: n.time.getTime(),
            read: n.read,
            actions: []  // Actions can't be invoked after restart
        }))
        notifStorage.setText(JSON.stringify(data, null, 2))
    }

    function saveSettings() {
        const data = {
            dndEnabled: dndEnabled,
            soundVolume: soundVolume,
            dingSoundSettings: dingSoundSettings,
            appDingOverrides: appDingOverrides
        }
        settingsStorage.setText(JSON.stringify(data, null, 2))
    }

    FileView {
        id: notifStorage
        path: Qt.resolvedUrl(root.notifStoragePath)

        onLoaded: {
            try {
                const data = JSON.parse(text())
                let maxId = 0
                data.forEach(n => {
                    maxId = Math.max(maxId, n.id)
                    const wrapper = notificationWrapperComponent.createObject(root, {
                        id: n.id,
                        summary: n.summary,
                        body: n.body,
                        appName: n.appName,
                        appIcon: n.appIcon,
                        image: n.image,
                        urgency: n.urgency,
                        time: new Date(n.time),
                        read: n.read,
                        isPopup: false
                    })
                    root.notifications.push(wrapper)
                })
                root.idOffset = maxId
                root.notifications = root.notifications.slice()
            } catch (e) {
                console.log("[NotificationCenter] Error loading notifications: " + e)
            }
        }

        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                console.log("[NotificationCenter] No saved notifications found")
            }
        }
    }

    FileView {
        id: settingsStorage
        path: Qt.resolvedUrl(root.settingsPath)

        onLoaded: {
            try {
                const data = JSON.parse(text())
                root.dndEnabled = data.dndEnabled ?? false
                root.soundVolume = data.soundVolume ?? 0.5
                root.dingSoundSettings = data.dingSoundSettings ?? root.dingSoundSettings
                root.appDingOverrides = data.appDingOverrides ?? {}
            } catch (e) {
                console.log("[NotificationCenter] Error loading settings: " + e)
            }
        }

        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                console.log("[NotificationCenter] No saved settings found, using defaults")
            }
        }
    }

    // Ensure data directory exists
    Process {
        id: mkdirProcess
        command: ["mkdir", "-p", root.dataDir + "/quickshell"]
        running: true
    }

    // =========================================================================
    // IPC Handler for CLI commands
    // =========================================================================

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.togglePanel()
        }

        function show(): void {
            root.showPanel()
        }

        function hide(): void {
            root.hidePanel()
        }

        function count(): string {
            return root.count.toString()
        }

        function unread(): string {
            return root.unreadCount.toString()
        }

        function clear(): void {
            root.dismissAll()
        }

        function dnd(): string {
            return root.dndEnabled ? "enabled" : "disabled"
        }

        function toggleDnd(): void {
            root.toggleDnd()
        }

        function ding(): void {
            root.playDing()
        }

        function setVolume(vol: string): void {
            root.soundVolume = parseFloat(vol)
            root.saveSettings()
        }
    }
}
