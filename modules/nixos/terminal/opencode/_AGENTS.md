# OpenCode Project Guidelines

## Core Principles

- **Parallel execution**: Spawn multiple agents for independent tasks to maximize throughput
- **Comment the WHY**: Explain non-obvious decisions, tradeoffs, and edge cases - not obvious operations
- **Test coverage**: Write comprehensive tests for all features; test-driven development encouraged
- **Keep docs updated**: Update README.md and relevant documentation after any changes

## Code Standards

- Descriptive names (no cryptic abbreviations)
- Single responsibility functions (≤3 params)
- Fail fast with clear error messages
- DRY: extract repeated logic into reusable functions

## Validation

Run linters after changes:

- TypeScript/JS: `lsp_diagnostics` clean
- Markdown: `markdown_lint_lint_markdown`
- QML: `qmllint_lint_qml`
- Nix: `statix check` + `nixfmt`

**No validation = incomplete.**
