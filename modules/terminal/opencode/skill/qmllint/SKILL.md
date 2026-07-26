---
name: qmllint
mcp:
  qmllint:
    type: stdio
    command: qmllint-mcp
description: Validate QML and Qt files when working on Quickshell or other QML-based configs.
---

# QMLLint

Use this when the task needs QML validation without enabling QML tooling globally for every OpenCode session.

## When to use

- Validating QML syntax
- Checking Qt/QML configuration files
- Investigating Quickshell or widget lint issues

## Why this is a skill

Keeping lint access local to the skill makes QML-specific tooling opt-in and easier to reason about.
