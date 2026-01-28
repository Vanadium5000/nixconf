/*
 * NotificationPopup.qml - Popup notification display
 */

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../lib"

PanelWindow {
    id: root

    required property var notificationService
    
    anchors {
        top: true
        right: true
    }
    
    margins {
        top: 10
        right: 10
    }

    width: 380
    height: popupColumn.implicitHeight + 20
    
    color: "transparent"
    
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-notification-popup"

    visible: notificationService.popups.length > 0

    ColumnLayout {
        id: popupColumn
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Repeater {
            model: root.notificationService.popups.slice(0, 5)

            NotificationItem {
                required property var modelData
                
                Layout.fillWidth: true
                notification: modelData
                isPopup: true
                
                onDismissed: root.notificationService.dismissNotification(modelData.id)
                onActionInvoked: (actionId) => root.notificationService.invokeAction(modelData.id, actionId)
                onCopyRequested: (text) => root.notificationService.copyToClipboard(text)
            }
        }
    }
}
