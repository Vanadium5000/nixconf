---
name: obsidian
mcp:
  obsidian_project:
    type: stdio
    command: opencode-obsidian-project-mcp
description: Use project-scoped Obsidian notes for docs, second-brain workflows, ADRs, and project memory.
---

# Obsidian Project Notes

Use this when the task benefits from durable project-scoped notes in the user's Obsidian vault without exposing the rest of `~/Vault`.

## Scope and safety

- The MCP wrapper exposes only `~/Vault/Projects/<project-slug>`.
- Do not ask for or assume access to unrelated vault paths.
- The project slug is derived from the current Git root basename, or the current directory basename outside Git worktrees.
- Treat notes as durable user-owned documentation: avoid deleting or mass-rewriting notes unless explicitly asked.

## When to use

- Writing or improving project documentation
- Capturing architectural decisions and tradeoffs
- Building project-specific second-brain context
- Recording research, runbooks, open questions, or session summaries

## Suggested layout

- `_index.md` — project overview and entry point
- `architecture/` — durable design notes
- `decisions/` — ADRs and decision records
- `docs/` — publishable documentation drafts
- `open-questions/` — unresolved questions and follow-ups
- `research/` — investigation notes and links
- `runbooks/` — operational procedures
- `session-logs/` — concise records of agent work

## Writing guidance

- Prefer small, linked Markdown notes over one giant file.
- Use clear frontmatter for durable notes when helpful.
- Capture why decisions were made, not only what changed.
- Link related project notes with normal Obsidian wiki links.
