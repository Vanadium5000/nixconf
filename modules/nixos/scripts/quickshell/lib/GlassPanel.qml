import QtQuick
import Qt5Compat.GraphicalEffects
import "."

Item {
    id: root
    
    default property alias content: container.children
    property alias color: backgroundRect.color
    property alias border: backgroundRect.border
    property bool hasShadow: true
    property bool hasBlur: true
    property bool hasBorder: true
    
    // Customization
    property real opacityValue: Theme.glassOpacity
    property int cornerRadius: Theme.rounding

    // The main visual container
    Rectangle {
        id: backgroundRect
        anchors.fill: parent
        radius: root.cornerRadius
        color: Theme.rgba(Theme.background, root.opacityValue)
        
        // --- 1. Background Blur (if supported by environment, otherwise implied by color) ---
        // Note: Real scene blur requires compositor support or specific shader. 
        // Here we simulate the "Glass" look with noise and gradients.

        // --- 2. Noise Texture for Frosted effect ---
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: "transparent"
            opacity: Theme.noiseOpacity
            visible: true
            
            // In a real setup, we'd use a ShaderEffect or Image for noise.
            // For now, we simulate texture with a very subtle pattern or just rely on color.
            // Placeholder for noise shader
        }

        // --- 3. Specular Highlight (Top Reflection) ---
        Rectangle {
            id: highlight
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height / 2
            radius: root.cornerRadius
            
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.rgba(Qt.color("white"), Theme.highlightOpacity) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            
            // Mask to keep it inside the rounded corners
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: backgroundRect
            }
        }

        // --- 4. Inner Stroke (Cut Glass Effect) ---
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: root.cornerRadius - 1
            color: "transparent"
            border.color: Theme.rgba(Qt.color("white"), 0.1)
            border.width: 1
            visible: true
        }

        // --- 5. Outer Border ---
        border.color: root.hasBorder ? Theme.rgba(Theme.accent, Theme.borderOpacity) : "transparent"
        border.width: Theme.borderWidth
    }

    // --- 6. Drop Shadow (Replacement for RectangularShadow) ---
    // Dummy item to cast shadow (avoids double rendering background)
    Rectangle {
        id: shadowCaster
        anchors.fill: backgroundRect
        radius: root.cornerRadius
        color: "black"
        visible: false
    }

    DropShadow {
        anchors.fill: shadowCaster
        source: shadowCaster
        z: -1
        radius: Theme.shadowRadius
        samples: (radius * 2) + 1
        color: Theme.rgba(Theme.background, Theme.shadowOpacity)
        visible: root.hasShadow
    }

    // Content Container
    Item {
        id: container
        anchors.fill: parent
        anchors.margins: Theme.gapsIn
    }
}
