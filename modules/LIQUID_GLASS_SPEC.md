# Apple Liquid Glass Design Specification

> A comprehensive implementation guide for the Liquid Glass design language,
> based on Apple's iOS 26 / macOS Tahoe design system (WWDC 2025), adapted for
> the Cyberpunk Electric Dark palette.

## Overview

**Liquid Glass** is Apple's most significant design evolution since iOS 7,
introduced at WWDC 2025. It creates translucent, dynamic materials that reflect
and refract surrounding content while transforming to bring focus to user
tasks.

### Core Principles

1. **Materiality**: Surfaces behave like physical glass slabs
2. **Depth**: Layered transparency creates spatial hierarchy
3. **Light Interaction**: Specular highlights and refractions respond to context
4. **Fluidity**: Smooth animations convey state changes organically

## Official Apple Values (from WWDC25 / HIG)

### Blur & Transparency Budgets

| Platform | Max Blur Radius | Recommended Frost |
| -------- | --------------- | ----------------- |
| iPhone   | ≤ 40px          | 10-25%            |
| iPad/Mac | ≤ 60px          | 10-25%            |

> Values > 30% look "milky plastic" and should be avoided.

### Material Variants (SwiftUI)

| Variant     | Description                         |
| ----------- | ----------------------------------- |
| `.regular`  | Medium transparency (default)       |
| `.clear`    | High transparency (media-rich BGs)  |
| `.identity` | No effect (conditional disabling)   |

### Shadow Tokens (SwiftUI Design System)

```swift
static let radius: CGFloat = 18
static let y: CGFloat = 8
static let opacity: Double = 0.18
```

### Border Stroke Tokens

```swift
static let width: CGFloat = 1
static let subtleOpacity: Double = 0.22
static let strongOpacity: Double = 0.35
```

### Corner Radii

| Element | Radius |
| ------- | ------ |
| Card    | 28px   |
| Pill    | 999px  |
| Sheet   | 34px   |

## Design Tokens (Cyberpunk Electric Dark)

### Color Palette

| Token           | Hex       | RGB                | Usage                |
| --------------- | --------- | ------------------ | -------------------- |
| `background`    | `#000000` | `rgb(0,0,0)`       | Primary glass tint   |
| `backgroundAlt` | `#141420` | `rgb(20,20,32)`    | Secondary surfaces   |
| `foreground`    | `#e0e0e0` | `rgb(224,224,224)` | Primary text         |
| `foregroundAlt` | `#d0d0d0` | `rgb(208,208,208)` | Secondary text       |
| `accent`        | `#5454fc` | `rgb(84,84,252)`   | Interactive elements |
| `accentAlt`     | `#54fcfc` | `rgb(84,252,252)`  | Active/hover states  |
| `error`         | `#fc5454` | `rgb(252,84,84)`   | Error states         |
| `success`       | `#54fc54` | `rgb(84,252,84)`   | Success states       |

### Glass Material Properties

| Property           | Value                      | Description                     |
| ------------------ | -------------------------- | ------------------------------- |
| `glassOpacity`     | `0.75`                     | Base transparency (75% opaque)  |
| `glassColor`       | `rgba(8,8,12,0.75)`        | Tinted dark glass               |
| `blurStrength`     | `8px` (main) + `1px` (bg)  | Two-layer blur system           |
| `highlightOpacity` | `0.18` top, `0.06` middle  | Specular gradient stops         |
| `innerStroke`      | `1px`                      | Inset border for depth          |
| `innerStrokeColor` | `rgba(255,255,255,0.08)`   | Subtle white edge               |

### Shadow Properties

| Property        | Value               | Description            |
| --------------- | ------------------- | ---------------------- |
| `shadowOpacity` | `0.50`              | Shadow alpha           |
| `shadowRadius`  | `18px`              | Blur radius            |
| `shadowOffsetY` | `6px`               | Vertical displacement  |
| `shadowColor`   | `rgba(0,0,0,0.5)`   | Pure black shadow      |

### Border Properties

| Property        | Value  | Description                       |
| --------------- | ------ | --------------------------------- |
| `borderWidth`   | `1px`  | Structural border thickness       |
| `borderOpacity` | `0.35` | Border visibility (35% of accent) |
| `outerGlow`     | `2px`  | Outer glow border width           |
| `outerGlowAlpha`| `0.15` | Outer glow opacity                |

### Layout Tokens

| Token           | Value  | Usage                              |
| --------------- | ------ | ---------------------------------- |
| `rounding`      | `16px` | Standard corner radius             |
| `roundingSmall` | `12px` | Buttons, list items                |
| `roundingLarge` | `26px` | Dialogs, large panels              |
| `gapsIn`        | `12px` | Internal spacing                   |
| `gapsOut`       | `16px` | External margins                   |

### Typography

| Token            | Value                     | Usage            |
| ---------------- | ------------------------- | ---------------- |
| `fontName`       | `JetBrainsMono Nerd Font` | All text         |
| `fontSize`       | `14px`                    | Body text        |
| `fontSizeSmall`  | `11px`                    | Captions, labels |
| `fontSizeLarge`  | `15px`                    | Headings         |
| `fontSizeXLarge` | `24px`                    | Display text     |

### Animation

| Property            | Value      | Description             |
| ------------------- | ---------- | ----------------------- |
| `animationDuration` | `120ms`    | State transition timing |
| `easing`            | `ease-out` | Deceleration curve      |

## Component Architecture

### GlassPanel Layer Stack

```text
┌─────────────────────────────────────────┐
│  ┌───────────────────────────────────┐  │ ← Outer glow (accent @ 15%)
│  │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  │ ← Specular gradient (18% → 6% → 0%)
│  │ ┌─────────────────────────────────┐│  │ ← Inner stroke (white @ 8%)
│  │ │                                 ││  │
│  │ │         CONTENT AREA            ││  │
│  │ │                                 ││  │
│  │ └─────────────────────────────────┘│  │
│  └───────────────────────────────────┘  │ ← Accent border (35%)
└─────────────────────────────────────────┘
           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓             ← Drop shadow (Y: 6px)
```

### Specular Highlight Gradient

```css
background: linear-gradient(
    to bottom,
    rgba(255, 255, 255, 0.18) 0%,
    rgba(255, 255, 255, 0.06) 30%,
    transparent 100%
);
```

### Button States

| State    | Background                 | Border                   | Highlight    |
| -------- | -------------------------- | ------------------------ | ------------ |
| Default  | `rgba(255,255,255,0.03)`   | `transparent`            | 4% white     |
| Hover    | `rgba(255,255,255,0.08)`   | `rgba(255,255,255,0.15)` | 6% white     |
| Active   | `rgba(accent,0.35)`        | `rgba(accent,0.6)`       | 12% white    |
| Pressed  | `rgba(accent,0.25)`        | `rgba(accent,0.5)`       | 8% white     |

## CSS Reference Implementation

```css
.liquid-glass {
    /* Base glass */
    background: rgba(8, 8, 12, 0.75);
    border-radius: 26px;
    border: 1px solid rgba(84, 84, 252, 0.35);
    position: relative;
    overflow: hidden;

    /* Shadow */
    box-shadow:
        0 6px 24px rgba(0, 0, 0, 0.5),
        inset 0 1px 0 rgba(255, 255, 255, 0.08);

    /* Blur (compositor-dependent) */
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
}

/* Outer glow */
.liquid-glass::before {
    content: '';
    position: absolute;
    inset: -2px;
    border-radius: 28px;
    border: 2px solid rgba(84, 84, 252, 0.15);
    pointer-events: none;
}

/* Specular highlight */
.liquid-glass::after {
    content: '';
    position: absolute;
    top: 1px;
    left: 1px;
    right: 1px;
    height: 40%;
    border-radius: 25px 25px 0 0;
    background: linear-gradient(
        to bottom,
        rgba(255, 255, 255, 0.18) 0%,
        rgba(255, 255, 255, 0.06) 30%,
        transparent 100%
    );
    pointer-events: none;
}

/* Button glass */
.glass-button {
    background: rgba(255, 255, 255, 0.03);
    border-radius: 12px;
    border: none;
    transition: all 120ms ease-out;
}

.glass-button:hover {
    background: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.15);
}

.glass-button.active {
    background: rgba(84, 84, 252, 0.35);
    border: 1px solid rgba(84, 84, 252, 0.6);
}
```

## Accessibility Guidelines

Per iOS 26.1, Apple added opacity controls. Provide options for:

| Setting              | Normal    | Reduced Transparency |
| -------------------- | --------- | -------------------- |
| `glassOpacity`       | 0.75      | 0.92                 |
| `highlightOpacity`   | 0.18      | 0.05                 |
| `borderOpacity`      | 0.35      | 0.60                 |
| Specular amplitude   | ≤ 6px     | disabled             |

### Opacity Priority System (Wireframing)

| Opacity | Usage                                    |
| ------- | ---------------------------------------- |
| 100%    | Vital content (main text, primary CTAs)  |
| 70%     | Supporting text, secondary buttons       |
| 40%     | Decorative UI (dividers, icons)          |
| 20%     | Subtle tints, atmospheric overlays       |

## File Reference

| File                  | Purpose                          |
| --------------------- | -------------------------------- |
| `lib/Theme.qml`       | Singleton with all design tokens |
| `lib/GlassPanel.qml`  | Container component              |
| `lib/GlassButton.qml` | Interactive button component     |
| `lib/qmldir`          | QML module definition            |

## References

- [WWDC25: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [SwiftUI glassEffect() API](https://developer.apple.com/documentation/SwiftUI/View/glassEffect)

## Version History

| Version | Date       | Changes                                       |
| ------- | ---------- | --------------------------------------------- |
| 1.0     | 2026-01-20 | Initial specification                         |
| 1.1     | 2026-01-20 | Updated with WWDC25 research, improved values |
