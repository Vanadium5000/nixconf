---
name: component
description: Create UI components with DaisyUI, Preact, and TypeScript
---

# Component Creation Skill

Guide for creating UI components with DaisyUI, Preact, and TypeScript.

## Invocation

`/component [component-name]`

Examples:

- `/component Button`
- `/component NotificationCard`
- `/component Modal`

## Pre-Creation Checklist

Before writing any code:

1. **Check DaisyUI**: Query `daisyui_get_component` for base patterns
2. **Check existing components**: Search codebase for similar patterns
3. **Research if needed**: Use `context7_query-docs` for Preact patterns

## DaisyUI-First Approach

Always start with DaisyUI components when possible:

```tsx
// ✅ Use DaisyUI classes
<button className="btn btn-primary">Click me</button>
<div className="card bg-base-100 shadow-xl">...</div>
<input className="input input-bordered" />

// ❌ Don't reinvent what DaisyUI provides
<button className="px-4 py-2 bg-blue-500 rounded">Click me</button>
```

## Component Structure (Preact + TypeScript)

```tsx
import { type JSX } from "preact";
import { useState } from "preact/hooks";

interface ComponentProps {
  /** Brief description of prop */
  title: string;
  /** Optional props use ? */
  variant?: "primary" | "secondary";
  /** Children if needed */
  children?: JSX.Element;
}

export function Component({
  title,
  variant = "primary",
  children,
}: ComponentProps): JSX.Element {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <div className="card bg-base-100">
      <div className="card-body">
        <h2 className="card-title">{title}</h2>
        {children}
        <div className="card-actions justify-end">
          <button
            className={`btn btn-${variant}`}
            onClick={() => setIsOpen(!isOpen)}
          >
            Action
          </button>
        </div>
      </div>
    </div>
  );
}
```

## TypeScript Patterns

### Const Types (Required)

```typescript
// ✅ ALWAYS: Create const object first, then extract type
const BUTTON_VARIANTS = {
  PRIMARY: "primary",
  SECONDARY: "secondary",
  GHOST: "ghost",
} as const;

type ButtonVariant = (typeof BUTTON_VARIANTS)[keyof typeof BUTTON_VARIANTS];

// ❌ NEVER: Direct union types
type ButtonVariant = "primary" | "secondary" | "ghost";
```

### Flat Interfaces (Required)

```typescript
// ✅ ALWAYS: One level depth, nested objects → dedicated interface
interface UserAddress {
  street: string;
  city: string;
}

interface User {
  id: string;
  name: string;
  address: UserAddress; // Reference, not inline
}

// ❌ NEVER: Inline nested objects
interface User {
  address: { street: string; city: string }; // NO!
}
```

### Import Types

```typescript
import type { User } from "./types";
import { createUser, type Config } from "./utils";
```

## Styling with Tailwind + DaisyUI

### Never Use var() in className

```tsx
// ❌ NEVER
<div className="bg-[var(--color-primary)]" />

// ✅ ALWAYS: Use DaisyUI/Tailwind semantic classes
<div className="bg-primary" />
```

### Never Use Hex Colors

```tsx
// ❌ NEVER
<p className="text-[#ffffff]" />

// ✅ ALWAYS: Use theme colors
<p className="text-base-content" />
```

### The cn() Utility

```typescript
import { clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

When to use:

```tsx
// ✅ Conditional classes
<div className={cn("base-class", isActive && "active-class")} />

// ✅ Merging with potential conflicts
<button className={cn("btn btn-primary", className)} />

// ❌ Static classes - unnecessary wrapper
<div className={cn("flex items-center")} /> // Just use className directly
```

## OpenAPI Integration

When components consume API data, use `typescript-swagger-api` generated types:

```typescript
// Import generated API client and types
import { Api, type User } from "./api/generated";

interface UserCardProps {
  user: User; // Use generated type directly
}

export function UserCard({ user }: UserCardProps): JSX.Element {
  return (
    <div className="card bg-base-100">
      <div className="card-body">
        <h2 className="card-title">{user.name}</h2>
        <p>{user.email}</p>
      </div>
    </div>
  );
}
```

## Accessibility Requirements

Every component MUST have:

- Semantic HTML elements (`button`, `nav`, `main`, not div soup)
- ARIA labels on icon-only buttons
- Keyboard navigation support (DaisyUI handles most of this)
- Visible focus states (DaisyUI provides these)

```tsx
// ✅ Good: semantic + accessible
<button className="btn btn-circle" aria-label="Close dialog">
  <IconX />
</button>

// ❌ Bad: div with click handler, no accessibility
<div onClick={onClose}>
  <IconX />
</div>
```

## Post-Creation Validation

1. Run TypeScript check: `tsc --noEmit`
2. Run linter: `eslint` or LSP diagnostics
3. Verify DaisyUI classes via `daisyui_get_component`
4. Check accessibility (semantic HTML, ARIA labels)
