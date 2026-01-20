# Apple Liquid Glass Design Specification

> A comprehensive implementation guide for the Liquid Glass design language,
> based on Apple's iOS 26 / macOS Tahoe design system, adapted for the
> Cyberpunk Electric Dark palette.

## Overview

**Liquid Glass** is Apple's most significant design evolution since iOS 7,
introduced at WWDC 2025. It creates translucent, dynamic materials that reflect
and refract surrounding content while transforming to bring focus to user
tasks.

### Core Principles

1. **Materiality**: Surfaces behave like physical glass slabs
2. **Depth**: Layered transparency creates spatial hierarchy
3. **Light Interaction**: Specular highlights and refractions respond to
   context
4. **Fluidity**: Smooth animations convey state changes organically

## Design Tokens

### Color Palette (Cyberpunk Electric Dark)

| Token           | Hex       | RGB                | Usage                |
| --------------- | --------- | ------------------ | -------------------- |
| `background`    | `#000000` | `rgb(0,0,0)`       | Primary glass tint   |
| `backgroundAlt` | `#0d0d0d` | `rgb(13,13,13)`    | Secondary surfaces   |
| `foreground`    | `#a8a8a8` | `rgb(168,168,168)` | Primary text         |
| `foregroundAlt` | `#d2d2d2` | `rgb(210,210,210)` | Emphasized text      |
| `accent`        | `#5454fc` | `rgb(84,84,252)`   | Interactive elements |
| `accentAlt`     | `#54fcfc` | `rgb(84,252,252)`  | Active/hover states  |
| `error`         | `#fc5454` | `rgb(252,84,84)`   | Error states         |
| `success`       | `#54fc54` | `rgb(84,252,84)`   | Success states       |

### Glass Material Properties

| Property           | Value                    | Description                            |
| ------------------ | ------------------------ | -------------------------------------- |
| `glassOpacity`     | `0.55`                   | Base transparency (55% opaque)         |
| `blurStrength`     | `40px`                   | Gaussian blur radius for backdrop      |
| `highlightOpacity` | `0.12`                   | Top-edge specular reflection intensity |
| `innerStroke`      | `1px`                    | Inset border for cut-glass effect      |
| `innerStrokeColor` | `rgba(255,255,255,0.08)` | Subtle white edge                      |
| `noiseOpacity`     | `0.02`                   | Frosted texture overlay                |

### Shadow Properties

| Property          | Value                    | Description              |
| ----------------- | ------------------------ | ------------------------ |
| `shadowOpacity`   | `0.6`                    | Shadow alpha             |
| `shadowRadius`    | `16px`                   | Blur radius              |
| `shadowOffsetY`   | `4px`                    | Vertical displacement    |
| `shadowColor`     | `rgba(0,0,0,0.6)`        | Pure black shadow        |

### Border Properties

| Property          | Value   | Description                            |
| ----------------- | ------- | -------------------------------------- |
| `borderWidth`     | `1px`   | Structural border thickness            |
| `borderOpacity`   | `0.25`  | Border visibility (25% of accent)      |

### Layout Tokens

| Token           | Value  | Usage                                    |
| --------------- | ------ | ---------------------------------------- |
| `rounding`      | `16px` | Standard corner radius                   |
| `roundingSmall` | `10px` | Buttons, small controls                  |
| `roundingLarge` | `24px` | Dialogs, large panels                    |
| `gapsIn`        | `6px`  | Internal spacing (between elements)      |
| `gapsOut`       | `12px` | External margins (panel to content)      |

### Typography

| Token            | Value                      | Usage              |
| ---------------- | -------------------------- | ------------------ |
| `fontName`       | `JetBrainsMono Nerd Font`  | All text           |
| `fontSize`       | `13px`                     | Body text          |
| `fontSizeSmall`  | `11px`                     | Captions, labels   |
| `fontSizeLarge`  | `16px`                     | Headings, prompts  |
| `fontSizeXLarge` | `24px`                     | Display text       |

### Animation

| Property            | Value      | Description                |
| ------------------- | ---------- | -------------------------- |
| `animationDuration` | `180ms`    | State transition timing    |
| `easing`            | `ease-out` | Deceleration curve         |

## Component Architecture

### GlassPanel (Container)

The fundamental building block for all glass surfaces.

```text
┌─────────────────────────────────────┐  ← Outer border (accent @ 25%)
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  ← Specular gradient (top 50%)
│ ┌─────────────────────────────────┐ │  ← Inner stroke (white @ 8%)
│ │                                 │ │
│ │          CONTENT AREA           │ │  ← Content with gapsIn margin
│ │                                 │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
         ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓            ← Drop shadow (offset Y: 4px)
```

#### Layer Stack (bottom to top)

1. **Drop Shadow**: `rgba(0,0,0,0.6)`, radius `16px`, offset Y `4px`
2. **Background**: `rgba(background, glassOpacity)`
3. **Specular Highlight**: Linear gradient, white `12%` → transparent
4. **Inner Stroke**: `1px` inset, `rgba(255,255,255,0.08)`
5. **Outer Border**: `1px`, `rgba(accent, 0.25)`
6. **Content**: Z-index `10`, margins `gapsIn`

### GlassButton (Interactive)

Buttons inherit glass properties with state-aware styling.

#### States

| State     | Background                  | Border                    |
| --------- | --------------------------- | ------------------------- |
| Default   | `rgba(background, 0.35)`    | `rgba(accent, 0.25)`      |
| Hover     | `rgba(foreground, 0.12)`    | `rgba(accent, 0.50)`      |
| Pressed   | `rgba(accent, 0.25)`        | `rgba(accent, 0.50)`      |
| Active    | `rgba(accent, 0.35)`        | `accent` (solid)          |

## QML Implementation

### Theme Singleton

```qml
pragma Singleton
import QtQuick

QtObject {
    readonly property color background: "#000000"
    readonly property real glassOpacity: 0.55
    readonly property real highlightOpacity: 0.12
    // ... (see lib/Theme.qml for complete implementation)

    function rgba(baseColor, alpha) {
        return Qt.rgba(baseColor.r, baseColor.g, baseColor.b, alpha)
    }
}
```

### GlassPanel Usage

```qml
import "./lib"

GlassPanel {
    width: 400
    height: 300
    cornerRadius: Theme.roundingLarge
    hasShadow: true
    hasBorder: true
    opacityValue: 0.55  // Override default if needed

    // Content goes here as children
    Text {
        text: "Hello, Glass!"
        color: Theme.foreground
    }
}
```

### GlassButton Usage

```qml
import "./lib"

GlassButton {
    text: "Click Me"
    icon: "🔥"  // Optional emoji or icon font glyph
    active: isSelected
    onClicked: doSomething()
}
```

## CSS Reference Implementation

For web or CSS-based systems:

```css
.glass-panel {
    background: rgba(0, 0, 0, 0.55);
    backdrop-filter: blur(40px);
    -webkit-backdrop-filter: blur(40px);
    border-radius: 16px;
    border: 1px solid rgba(84, 84, 252, 0.25);
    box-shadow:
        0 4px 16px rgba(0, 0, 0, 0.6),
        inset 0 1px 0 rgba(255, 255, 255, 0.08);
    position: relative;
}

.glass-panel::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 50%;
    border-radius: 16px 16px 0 0;
    background: linear-gradient(
        to bottom,
        rgba(255, 255, 255, 0.12) 0%,
        rgba(255, 255, 255, 0.02) 60%,
        transparent 100%
    );
    pointer-events: none;
}
```

## Accessibility Considerations

Per iOS 26.1, Apple added opacity controls for users who find Liquid Glass
difficult to read. Consider providing:

- **Reduce Transparency**: Increase `glassOpacity` to `0.85+`
- **Increase Contrast**: Boost `borderOpacity` and `highlightOpacity`
- **Reduce Motion**: Extend `animationDuration` or disable animations

## File Reference

| File                  | Purpose                              |
| --------------------- | ------------------------------------ |
| `lib/Theme.qml`       | Singleton with all design tokens     |
| `lib/GlassPanel.qml`  | Container component                  |
| `lib/GlassButton.qml` | Interactive button component         |
| `lib/qmldir`          | QML module definition                |

## Version History

| Version | Date       | Changes                                  |
| ------- | ---------- | ---------------------------------------- |
| 1.0     | 2026-01-20 | Initial specification                    |
