---
name: shadcn-ui
description: Use shadcn/ui CLI, MCP, and project metadata before writing components
---

# Shadcn UI Workflow

Use this skill when a project uses shadcn/ui or has a `components.json` file.

## Preferred flow

1. Confirm the project root contains `components.json`.
2. If `components.json` is missing, initialize shadcn/ui before adding components.
3. Use the `shadcn` MCP to browse, search, and install registry items before hand-writing UI code.
4. Prefer `shadcn info --json` and the current `components.json` to infer aliases, paths, registry namespaces, icon library, and base library.
5. After installing or updating components, run the project's normal lint, typecheck, and browser verification flow.

## Accuracy rules

- Treat `components.json` as the source of truth for aliases, registries, and resolved UI paths.
- Prefer registry installs over recreating components from memory.
- Preserve existing local conventions around routing, forms, and styling utilities.
- When adding forms, tables, dashboards, or auth flows, search the registry first for an existing block or component set.

## MCP-first prompts

- Show available components in the configured registries.
- Search the registry for the requested UI pattern before coding.
- Install the exact shadcn/ui component or block, then adapt it to the project.

## Notes

- Official references: `https://ui.shadcn.com/docs/skills` and `https://ui.shadcn.com/docs/mcp`
- This project-local skill exists so shadcn guidance follows the repo instead of changing every OpenCode session globally.
