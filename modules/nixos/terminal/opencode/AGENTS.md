# OpenCode Project Guidelines

## Coding Standards

### Naming

- Descriptive, meaningful names - purpose clear from name
- Consistent patterns across codebase
- No abbreviations (except `i`, `j`, `k` loop counters)
- Searchable constant names: `MAX_RETRY_ATTEMPTS` not `max`

```typescript
// Good: intent is clear
const userAuthToken = generateToken();
function calculateCompoundInterest(principal, rate, time) {}

// Bad: cryptic, unsearchable
const tkn = gen();
function calc(p, r, t) {}
```

### Functions

- Single responsibility - one reason to change
- ≤3 parameters (use options object if more needed)
- Return early to reduce nesting
- Name indicates action: `fetchUser`, `validateInput`, `calculateTotal`

```python
# Good: early return, focused
def get_order_total(items: List[Item]) -> Decimal:
    if not items:
        return Decimal('0.00')
    return sum(i.price * i.quantity for i in items)

# Bad: deep nesting, mixed concerns
def process(data):
    if data:
        if data.valid:
            # 50 more lines...
```

### Error Handling

- Validate inputs at boundaries
- Fail fast with clear messages
- Never swallow errors silently

```typescript
function divide(a: number, b: number): number {
    if (b === 0) throw new Error('Division by zero');
    if (!Number.isFinite(a)) throw new Error(`Invalid dividend: ${a}`);
    return a / b;
}
```

### DRY & SOLID

- Extract repeated logic into reusable functions
- Single Responsibility: one module = one concern
- Depend on abstractions, not concretions
- Prefer composition over inheritance

### Technical Inline Comments (CRITICAL)

**Comment the WHY, not the WHAT.** Every non-obvious decision needs explanation.

#### MUST Comment

| Situation | Example |
| ----------- | --------- |
| Magic numbers | `timeout = 3000; // 3s - reduced from 5s for faster fallback` |
| Non-obvious values | `bufferSize = 4096; // 4KB - matches filesystem block size` |
| Format/syntax | `"[::1]:53" // IPv6 loopback` |
| Workarounds | `// HACK: upstream bug #1234 - remove after v2.1` |
| Tradeoffs | `// O(n²) acceptable here - list always < 100 items` |
| Edge cases | `// Empty string valid - represents "use default"` |
| External dependencies | `// Requires libfoo >= 2.0 for async support` |
| Business logic | `// 30-day window per compliance requirement XYZ` |

#### NEVER Comment

| Anti-pattern | Why it's bad |
|--------------|--------------|
| `enable = true; // Enable feature` | Tautology - code says this |
| `i++; // Increment i` | Obvious operation |
| `// Import module` above import | Self-evident |

#### Comment Format

```typescript
// Single line for brief context
const retryDelay = 1000; // 1s exponential backoff base

// Multi-line for complex rationale
// We use a bloom filter here instead of a hash set because:
// 1. Memory: 10MB vs 400MB for 50M entries
// 2. False positives acceptable (we verify against DB anyway)
// 3. No deletions needed in this use case
const filter = new BloomFilter(expectedItems, falsePositiveRate);

// TODO/FIXME with context
// TODO(matrix): Replace with native API when Node 22 ships
// FIXME: Race condition under high load - see issue #456
```

### Code Readability

- 80-120 char line limit
- Consistent formatting (use project formatter)
- Whitespace for visual grouping
- Group related code together

## Web Search for Research

**ALWAYS use the `websearch` MCP (Exa) for research tasks.** This includes:

- Looking up documentation for unfamiliar APIs or libraries
- Researching best practices and design patterns
- Finding solutions to errors or debugging issues
- Verifying current behavior of external services
- Checking for security advisories or known issues

### When to Search

| Situation | Action |
| ----------- |--------|
| Unfamiliar library/API | Search before implementing |
| Error message you don't recognize | Search for solutions |
| "Is this the right approach?" | Search for best practices |
| Security-sensitive code | Search for advisories |
| External service integration | Search for current docs |

### How to Search

Use the `websearch_web_search_exa` tool:

```text
websearch_web_search_exa(query="your search query", numResults=8)
```

For comprehensive research, use `type="deep"`:

```text
websearch_web_search_exa(query="complex topic", type="deep")
```

## Linting on File Changes

**ALWAYS use available lint MCPs after making changes to files.**

### Available Lint MCPs

| File Extension | Linter | Tool |
|----------------|--------|------|
| `.md` | markdownlint | `markdown_lint_lint_markdown` |
| `.qml` | qmllint | `qmllint_lint_qml` |

For directory-wide linting:

| File Extension | Tool |
|----------------|------|
| `.md` | `markdown_lint_lint_markdown_directory` |
| `.qml` | `qmllint_lint_qml_directory` |

### Linting Protocol

1. **After editing a file**, check if a linter is available for that file type
2. **Run the linter** on the modified file
3. **Fix any errors** reported by the linter before considering the task complete
4. **Re-run the linter** to verify fixes

### Examples

After editing a Markdown file:

```text
markdown_lint_lint_markdown(filePath="/path/to/file.md")
```

After editing a QML file:

```text
qmllint_lint_qml(filePath="/path/to/file.qml")
```

Directory-wide validation:

```typescript
qmllint_lint_qml_directory({
  directoryPath: "/home/matrix/nixconf/modules/hjem/quickshell",
  maxDepth: 50
})

markdown_lint_lint_markdown_directory({
  directoryPath: "/home/matrix/nixconf"
})
```

### Linting Checklist

Before marking any file edit as complete:

- [ ] Identified file type
- [ ] Checked if linter is available for that type
- [ ] Ran linter on the file
- [ ] Fixed all reported issues
- [ ] Re-ran linter to confirm clean output

## Code Patterns

### Nix Files

- Use `nixfmt` (RFC style) for formatting
- Run `statix check` for linting
- Follow patterns in existing codebase

### TypeScript/JavaScript

- Use project's configured formatter/linter (usually via LSP)
- Check `lsp_diagnostics` after changes

### QML Files

- **MUST** run `qmllint_lint_qml` after any QML changes
- Follow Quickshell patterns from `quickshell_*` tools

### Markdown Files

- **MUST** run `markdown_lint_lint_markdown` after any Markdown changes
- Keep lines under 80 characters where practical
- Use ATX-style headers (`#` not underlines)

## Research Tools

| Tool | Purpose | When to Use |
| ---- | ------- | ----------- |
| `context7_*` | Official library docs | Unfamiliar APIs, correct usage patterns |
| `deepwiki_*` | GitHub repo documentation | Understanding external projects |
| `quickshell_*` | Quickshell-specific docs | QML/Quickshell implementation |
| `gh_grep_searchGitHub` | Real-world code examples | Production patterns, edge cases |
| `websearch_*` | General web search | Current info, news, broad topics |

## Evidence Requirements

A task is NOT complete without validation evidence:

| Change Type | Required Validation |
| ----------- | ------------------- |
| TypeScript/JS | `lsp_diagnostics` clean |
| QML files | `qmllint_lint_qml` or `qmllint_lint_qml_directory` |
| Markdown | `markdown_lint_lint_markdown` or directory variant |
| Nix files | `statix check` + `nixfmt --check` |
| Any code | Build/test commands if available |

**NO VALIDATION = NOT COMPLETE.**
