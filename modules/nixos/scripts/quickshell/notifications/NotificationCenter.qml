/*
 * NotificationCenter.qml - Notification Service Singleton
 *
 * Core notification service that manages the notification server,
 * persistence, and sound system.
 */

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    // =========================================================================
    // Public Properties
    // =========================================================================

    property var notifications: []
    readonly property var popups: notifications.filter(n => n.isPopup)
    readonly property int count: notifications.length
    readonly property int unreadCount: notifications.filter(n => !n.read).length

    property bool dndEnabled: false
    property bool panelVisible: false
    property real soundVolume: 0.5

    // Popup timeout settings (in milliseconds)
    property int defaultPopupTimeout: 7000  // 7s default for timeout=-1 notifications

    // Ding sound settings per urgency level
    property var dingSoundSettings: ({
        "low": false,
        "normal": true,
        "critical": true
    })

    // Per-app ding overrides (appName -> bool)
    property var appDingOverrides: ({})

    // Regex patterns that always trigger ding (array of pattern strings)
    property var dingPatterns: []

    // =========================================================================
    // Signals
    // =========================================================================

    signal notificationReceived(var notification)
    signal notificationDismissed(int id)
    signal panelToggled(bool visible)
    signal playDingSignal()

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

    function dismissNotification(id) {
        const index = notifications.findIndex(n => n.id === id)
        if (index !== -1) {
            const notif = notifications[index]
            if (notif.notification) {
                notif.notification.dismiss()
            }
            notifications.splice(index, 1)
            notifications = notifications.slice()
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

    function invokeAction(notifId, actionIdentifier) {
        const notif = notifications.find(n => n.id === notifId)
        if (notif && notif.notification) {
            const action = notif.notification.actions.find(a => a.identifier === actionIdentifier)
            if (action) {
                action.invoke()
            }
        }
        dismissNotification(notifId)
    }

    function copyToClipboard(text) {
        Quickshell.clipboardText = text
    }

    function setDingForApp(appName, enabled) {
        appDingOverrides[appName] = enabled
        appDingOverrides = Object.assign({}, appDingOverrides)
        saveSettings()
    }

    function setDingForUrgency(urgency, enabled) {
        dingSoundSettings[urgency] = enabled
        dingSoundSettings = Object.assign({}, dingSoundSettings)
        saveSettings()
    }

    function addDingPattern(pattern) {
        if (pattern && pattern.trim() !== "" && !dingPatterns.includes(pattern)) {
            dingPatterns = [...dingPatterns, pattern]
            saveSettings()
        }
    }

    function removeDingPattern(pattern) {
        dingPatterns = dingPatterns.filter(p => p !== pattern)
        saveSettings()
    }

    function toggleDnd() {
        dndEnabled = !dndEnabled
        saveSettings()
    }

    function playDing() {
        playDingSignal()
    }

    // =========================================================================
    // Internal: Create notification wrapper object
    // =========================================================================

    function createNotificationWrapper(id, notification, isPopup, time) {
        var urgencyVal = notification ? notification.urgency : 1
        var urgencyStr = "normal"
        if (urgencyVal === 0) urgencyStr = "low"
        else if (urgencyVal === 2) urgencyStr = "critical"

        return {
            id: id,
            notification: notification,
            isPopup: isPopup,
            read: false,
            time: time || new Date(),
            summary: notification ? notification.summary : "",
            body: notification ? notification.body : "",
            appName: notification ? notification.appName : "",
            appIcon: notification ? notification.appIcon : "",
            image: notification ? notification.image : "",
            urgency: urgencyVal,
            urgencyString: urgencyStr,
            actions: notification ? notification.actions.map(a => ({
                identifier: a.identifier,
                text: a.text
            })) : [],
            popupExpiresAt: null,  // Set when notification becomes a popup
            get timeAgo() {
                const now = new Date()
                const diff = Math.floor((now - this.time) / 1000)
                if (diff < 60) return "now"
                if (diff < 3600) return Math.floor(diff / 60) + "m"
                if (diff < 86400) return Math.floor(diff / 3600) + "h"
                return Math.floor(diff / 86400) + "d"
            },
            get secondsRemaining() {
                if (!this.popupExpiresAt) return -1
                const remaining = Math.ceil((this.popupExpiresAt.getTime() - Date.now()) / 1000)
                return Math.max(0, remaining)
            }
        }
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
            const wrapper = root.createNotificationWrapper(
                newId,
                notification,
                !root.dndEnabled && !root.panelVisible,
                new Date()
            )

            // Set up popup expiry time based on notification's timeout
            // expireTimeout: -1 = use server default, 0 = never expire, >0 = ms
            if (wrapper.isPopup) {
                const expireTimeout = notification.expireTimeout
                if (expireTimeout === 0) {
                    // Explicit "never expire" - no auto-dismiss, stays until manual action
                    wrapper.popupExpiresAt = null
                } else {
                    // Use notification timeout if positive, otherwise use default (7s)
                    const timeout = (expireTimeout > 0) ? expireTimeout : root.defaultPopupTimeout
                    wrapper.popupExpiresAt = new Date(Date.now() + timeout)
                }
            }

            root.notifications = [wrapper, ...root.notifications]
            root.notificationReceived(wrapper)

            // Play ding sound if enabled
            root.maybePlayDing(wrapper)

            root.saveNotifications()
        }
    }

    // Periodic timer to check popup expiry and refresh time displays
    Timer {
        id: popupExpiryChecker
        interval: 1000  // Check every second
        running: true
        repeat: true
        onTriggered: {
            const now = Date.now()
            let changed = false

            root.notifications.forEach(n => {
                // Check if popup has expired (only if popupExpiresAt is set)
                if (n.isPopup && n.popupExpiresAt && now >= n.popupExpiresAt.getTime()) {
                    n.isPopup = false
                    changed = true
                }
            })

            // Always trigger reactivity to update timeAgo/secondsRemaining displays
            root.notifications = root.notifications.slice()
        }
    }

    // =========================================================================
    // Sound System
    // =========================================================================

    function maybePlayDing(notif) {
        if (root.dndEnabled) return

        // Check regex patterns first (highest priority)
        for (var i = 0; i < root.dingPatterns.length; i++) {
            try {
                var regex = new RegExp(root.dingPatterns[i], "i")
                if (regex.test(notif.appName) || regex.test(notif.summary)) {
                    root.playDingSignal()
                    return
                }
            } catch (e) {
                console.log("[NotificationCenter] Invalid regex pattern: " + root.dingPatterns[i])
            }
        }

        // Check app-specific override
        if (notif.appName in root.appDingOverrides) {
            if (root.appDingOverrides[notif.appName]) {
                root.playDingSignal()
            }
            return
        }

        // Fall back to urgency-based setting
        if (root.dingSoundSettings[notif.urgencyString]) {
            root.playDingSignal()
        }
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
            actions: []
        }))
        notifStorage.setText(JSON.stringify(data, null, 2))
    }

    function saveSettings() {
        const data = {
            dndEnabled: dndEnabled,
            soundVolume: soundVolume,
            dingSoundSettings: dingSoundSettings,
            appDingOverrides: appDingOverrides,
            dingPatterns: dingPatterns
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
                    const wrapper = root.createNotificationWrapper(n.id, null, false, new Date(n.time))
                    wrapper.summary = n.summary
                    wrapper.body = n.body
                    wrapper.appName = n.appName
                    wrapper.appIcon = n.appIcon
                    wrapper.image = n.image
                    wrapper.urgency = n.urgency
                    wrapper.read = n.read
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
                root.dingPatterns = data.dingPatterns ?? []
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
