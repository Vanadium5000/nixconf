import QtQuick 2.15
import "." 1.0

Item {
    id: root
    
    property string text: ""
    property string icon: ""
    property bool active: false
    signal clicked()

    implicitWidth: 120
    implicitHeight: 40

    // Hover state
    property bool hovered: hoverHandler.hovered
    property bool pressed: tapHandler.pressed

    GlassPanel {
        anchors.fill: parent
        cornerRadius: Theme.rounding
        
        // Dynamic styling based on state
        color: {
            if (root.active) return Theme.rgba(Theme.accent, 0.3)
            if (root.pressed) return Theme.rgba(Theme.accent, 0.2)
            if (root.hovered) return Theme.rgba(Theme.foreground, 0.1)
            return Theme.rgba(Theme.background, 0.3)
        }
        
        border.color: {
            if (root.active) return Theme.accent
            if (root.hovered) return Theme.rgba(Theme.accent, 0.5)
            return Theme.rgba(Theme.accent, Theme.borderOpacity)
        }
        
        opacityValue: root.hovered ? 0.6 : 0.45
        hasShadow: root.hovered
        
        // Animation for hover states
        Behavior on color { ColorAnimation { duration: Theme.animationDuration } }
        Behavior on opacityValue { NumberAnimation { duration: Theme.animationDuration } }
        
        RowLayout {
            anchors.centerIn: parent
            spacing: 8
            
            // Icon (if present)
            Text {
                visible: root.icon !== ""
                text: root.icon
                font.family: Theme.fontName
                font.pixelSize: Theme.fontSizeLarge
                color: root.active ? Theme.accentAlt : Theme.foreground
            }
            
            // Label
            Text {
                text: root.text
                font.family: Theme.fontName
                font.pixelSize: Theme.fontSize
                color: root.active ? Theme.accentAlt : Theme.foreground
                font.bold: root.active
            }
        }
    }

    HoverHandler {
        id: hoverHandler
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        onTapped: root.clicked()
    }
}
