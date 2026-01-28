---
name: coding-standards
globs: "**/*"
alwaysApply: true
description: Universal coding standards - clean code, naming, structure, inline documentation
---

# Coding Standards

## Naming

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

## Functions

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

## Error Handling

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

## DRY & SOLID

- Extract repeated logic into reusable functions
- Single Responsibility: one module = one concern
- Depend on abstractions, not concretions
- Prefer composition over inheritance

## Technical Inline Comments (CRITICAL)

**Comment the WHY, not the WHAT.** Every non-obvious decision needs explanation.

### MUST Comment

| Situation | Example |
|-----------|---------|
| Magic numbers | `timeout = 3000; // 3s - reduced from 5s for faster fallback` |
| Non-obvious values | `bufferSize = 4096; // 4KB - matches filesystem block size` |
| Format/syntax | `"[::1]:53" // IPv6 loopback` |
| Workarounds | `// HACK: upstream bug #1234 - remove after v2.1` |
| Tradeoffs | `// O(n²) acceptable here - list always < 100 items` |
| Edge cases | `// Empty string valid - represents "use default"` |
| External dependencies | `// Requires libfoo >= 2.0 for async support` |
| Business logic | `// 30-day window per compliance requirement XYZ` |

### NEVER Comment

| Anti-pattern | Why it's bad |
|--------------|--------------|
| `enable = true; // Enable feature` | Tautology - code says this |
| `i++; // Increment i` | Obvious operation |
| `// Import module` above import | Self-evident |

### Comment Format

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

## Code Readability

- 80-120 char line limit
- Consistent formatting (use project formatter)
- Whitespace for visual grouping
- Group related code together
