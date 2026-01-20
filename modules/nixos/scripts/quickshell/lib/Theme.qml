pragma Singleton
import QtQuick

QtObject {
    id: root

    // === Core Colors (Cyberpunk Electric Dark Palette) ===
    readonly property color background: "#000000"
    readonly property color backgroundAlt: "#0d0d0d"
    readonly property color foreground: "#a8a8a8"
    readonly property color foregroundAlt: "#d2d2d2"
    readonly property color accent: "#5454fc"
    readonly property color accentAlt: "#54fcfc"
    readonly property color error: "#fc5454"
    readonly property color success: "#54fc54"

    // === Liquid Glass Material Properties ===
    // Based on Apple's Liquid Glass design language (iOS 26 / macOS Tahoe)

    // Glass transparency - how much background shows through
    readonly property real glassOpacity: 0.55

    // Blur strength in pixels (compositor-dependent)
    readonly property real blurStrength: 40.0

    // Border visibility on glass panels
    readonly property real borderOpacity: 0.25

    // Specular highlight on top edge (simulates light reflection)
    readonly property real highlightOpacity: 0.12

    // Drop shadow properties
    readonly property real shadowOpacity: 0.6
    readonly property real shadowRadius: 16.0
    readonly property real shadowOffsetY: 4.0

    // Inner stroke (cut-glass edge effect)
    readonly property real innerStroke: 1.0
    readonly property color innerStrokeColor: Qt.rgba(1, 1, 1, 0.08)

    // Subtle noise texture overlay
    readonly property real noiseOpacity: 0.02

    // Animation timing
    readonly property int animationDuration: 180

    // === Layout Tokens ===
    readonly property int rounding: 16
    readonly property int roundingSmall: 10
    readonly property int roundingLarge: 24
    readonly property int gapsIn: 6
    readonly property int gapsOut: 12
    readonly property int borderWidth: 1

    // === Typography ===
    readonly property string fontName: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 13
    readonly property int fontSizeSmall: 11
    readonly property int fontSizeLarge: 16
    readonly property int fontSizeXLarge: 24

    // === Helper Functions ===
    function rgba(baseColor, alpha) {
        return Qt.rgba(baseColor.r, baseColor.g, baseColor.b, alpha)
    }
}
