/*
 * Theme.qml - Apple Liquid Glass Design System Theme
 *
 * This singleton provides design tokens for implementing Apple's Liquid Glass
 * visual language (iOS 26 / macOS Tahoe) in Quickshell applications.
 *
 * The theme is split into two sections:
 * 1. App Theme (colors) - Cyberpunk Electric Dark palette for terminal/apps
 * 2. Glass Theme (glass) - Official Apple Liquid Glass UI values
 *
 * Usage:
 *   import "./lib"
 *   Rectangle { color: Theme.glass.backgroundColor }
 *   Text { color: Theme.colors.accent }
 */

pragma Singleton
import QtQuick

QtObject {
    id: root

    // =========================================================================
    // APP THEME - Cyberpunk Electric Dark Palette
    // Used for terminal applications, syntax highlighting, app-specific styling
    // =========================================================================

    readonly property QtObject colors: QtObject {
        // Base16 color scheme
        readonly property color base00: "#000000"  // Background
        readonly property color base01: "#0d0d0d"  // Lighter background
        readonly property color base02: "#383838"  // Selection background
        readonly property color base03: "#545454"  // Comments, invisibles
        readonly property color base04: "#7e7e7e"  // Dark foreground
        readonly property color base05: "#a8a8a8"  // Default foreground
        readonly property color base06: "#d2d2d2"  // Light foreground
        readonly property color base07: "#fcfcfc"  // Lightest foreground

        // Accent colors
        readonly property color red: "#fc5454"
        readonly property color orange: "#a85400"
        readonly property color yellow: "#fcfc54"
        readonly property color green: "#54fc54"
        readonly property color cyan: "#54fcfc"
        readonly property color blue: "#5454fc"
        readonly property color magenta: "#fc54fc"
        readonly property color darkGreen: "#00a800"

        // Semantic aliases
        readonly property color accent: blue
        readonly property color accentAlt: cyan
        readonly property color background: base00
        readonly property color backgroundAlt: base01
        readonly property color foreground: base05
        readonly property color foregroundAlt: base06
        readonly property color border: blue
        readonly property color borderInactive: base03
        readonly property color error: red
        readonly property color success: green
        readonly property color warning: yellow
    }

    // =========================================================================
    // LIQUID GLASS UI THEME - Official Apple Dark Mode Values
    // Based on WWDC25 specifications and iOS 26 Human Interface Guidelines
    // =========================================================================

    readonly property QtObject glass: QtObject {
        // ---------------------------------------------------------------------
        // Colors - Apple Dark Mode Liquid Glass
        // ---------------------------------------------------------------------

        // Primary glass background (translucent dark material)
        // Apple uses a slightly blue-tinted dark for depth perception
        // rgba(15, 15, 23, 0.78)
        readonly property color backgroundColor: Qt.rgba(0.06, 0.06, 0.09, 0.78)
        readonly property color backgroundSolid: "#1C1C1E"

        // Accent colors (Apple Blue for dark mode)
        readonly property color accentColor: "#0A84FF"      // iOS system blue (dark)
        readonly property color accentColorAlt: "#64D2FF"   // iOS system cyan (dark)

        // Text hierarchy (Apple SF Pro values)
        readonly property color textPrimary: "#FFFFFF"      // Primary labels
        readonly property color textSecondary: "#EBEBF5"    // Secondary labels (60% opacity equiv)
        readonly property color textTertiary: Qt.rgba(0.92, 0.92, 0.96, 0.3)  // Tertiary/placeholder

        // Separators and dividers
        readonly property color separator: Qt.rgba(0.33, 0.33, 0.35, 0.65)
        readonly property color separatorOpaque: "#38383A"

        // ---------------------------------------------------------------------
        // Glass Material Properties
        // ---------------------------------------------------------------------

        // Specular highlight (top edge reflection)
        readonly property real highlightOpacity: 0.15

        // Inner stroke (cut-glass depth effect)
        readonly property color innerStrokeColor: Qt.rgba(1, 1, 1, 0.06)

        // Border properties
        readonly property real borderOpacity: 0.28
        readonly property int borderWidth: 1

        // Shadow properties (Apple design tokens)
        readonly property real shadowOpacity: 0.45
        readonly property real shadowRadius: 20
        readonly property real shadowOffsetY: 6

        // Backdrop blur (compositor-dependent)
        readonly property real blurRadius: 40

        // ---------------------------------------------------------------------
        // Layout Tokens
        // ---------------------------------------------------------------------

        readonly property int cornerRadius: 22      // Large panels/dialogs
        readonly property int cornerRadiusSmall: 12 // Buttons, list items
        readonly property int padding: 14           // Internal panel padding
        readonly property int itemSpacing: 10      // Between list items

        // ---------------------------------------------------------------------
        // Typography (SF Pro equivalents)
        // ---------------------------------------------------------------------

        readonly property string fontFamily: "JetBrainsMono Nerd Font"
        readonly property int fontSizeSmall: 11
        readonly property int fontSizeMedium: 14
        readonly property int fontSizeLarge: 17
        readonly property int fontSizeTitle: 22

        // ---------------------------------------------------------------------
        // Animation
        // ---------------------------------------------------------------------

        readonly property int animationDuration: 150  // State transitions (ms)
        readonly property int animationDurationSlow: 250
    }

    // =========================================================================
    // Legacy Compatibility - Flat property access
    // Deprecated: Use Theme.colors.* or Theme.glass.* instead
    // =========================================================================

    readonly property color background: colors.background
    readonly property color backgroundAlt: colors.backgroundAlt
    readonly property color foreground: colors.foreground
    readonly property color foregroundAlt: colors.foregroundAlt
    readonly property color accent: colors.accent
    readonly property color accentAlt: colors.accentAlt
    readonly property color error: colors.error
    readonly property color success: colors.success

    readonly property string fontName: glass.fontFamily
    readonly property int fontSize: glass.fontSizeMedium
    readonly property int fontSizeSmall: glass.fontSizeSmall
    readonly property int fontSizeLarge: glass.fontSizeLarge

    readonly property int rounding: glass.cornerRadius
    readonly property int gapsIn: glass.itemSpacing
    readonly property int gapsOut: glass.padding

    // =========================================================================
    // Helper Functions
    // =========================================================================

    /**
     * Create an RGBA color from a base color with custom alpha.
     * @param baseColor - The color to modify
     * @param alpha - Opacity value (0.0 - 1.0)
     * @returns Qt color with modified alpha
     */
    function rgba(baseColor, alpha) {
        return Qt.rgba(baseColor.r, baseColor.g, baseColor.b, alpha);
    }
}
