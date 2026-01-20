pragma Singleton
import QtQuick
import Quickshell

QtObject {
    id: root

    // --- Core Colors (Cyberpunk Electric Dark) ---
    property color background: "#000000"
    property color backgroundAlt: "#0d0d0d"
    property color foreground: "#a8a8a8"
    property color foregroundAlt: "#d2d2d2"
    property color accent: "#5454fc"
    property color accentAlt: "#54fcfc"
    property color error: "#fc5454"
    property color success: "#54fc54"

    // --- Liquid Glass Properties ---
    property real glassOpacity: 0.45
    property real blurStrength: 40
    property real borderOpacity: 0.3
    property real highlightOpacity: 0.15
    property real shadowOpacity: 0.5
    property real shadowRadius: 12
    property real innerStroke: 1
    property real noiseOpacity: 0.03
    property int animationDuration: 200

    // --- Layout ---
    property int rounding: 16
    property int gapsIn: 6
    property int gapsOut: 12
    property int borderWidth: 2

    // --- Fonts ---
    property string fontName: "JetBrainsMono Nerd Font"
    property int fontSize: 13
    property int fontSizeSmall: 11
    property int fontSizeLarge: 16

    // --- Helper Functions ---
    function rgba(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity)
    }
}
