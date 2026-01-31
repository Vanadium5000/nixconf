---
name: frontend-review
description: Comprehensive frontend code review checklist
---

# Frontend Review Skill

Systematic review process for frontend code changes.

## Invocation

`/frontend-review [file-or-directory]`

## Review Checklist

### 1. Accessibility (a11y)

- [ ] Semantic HTML elements (`button`, `nav`, `main`, not div soup)
- [ ] ARIA labels on icon-only interactive elements
- [ ] Alt text on images
- [ ] Keyboard navigation works
- [ ] Focus states visible
- [ ] Color contrast sufficient (4.5:1 for text)

### 2. Responsive Design

- [ ] Mobile-first approach
- [ ] Breakpoints: sm (640), md (768), lg (1024), xl (1280)
- [ ] Touch targets at least 44x44px
- [ ] No horizontal scroll on mobile
- [ ] Images responsive (srcset or CSS)

### 3. DaisyUI Compliance

- [ ] Using DaisyUI components where applicable
- [ ] Theme colors used (`primary`, `secondary`, `base-content`)
- [ ] No hardcoded hex colors in className
- [ ] No `var()` in className
- [ ] Proper component classes (`btn`, `card`, `input`, etc.)

### 4. TypeScript Quality

- [ ] No `any` types (use `unknown` + type guards)
- [ ] Const types pattern for enums/unions
- [ ] Flat interfaces (no inline nested objects)
- [ ] Props interfaces have JSDoc comments
- [ ] Import types with `import type`

### 5. Performance

- [ ] Images optimized (WebP, lazy loading)
- [ ] No unnecessary re-renders
- [ ] Large lists virtualized
- [ ] No blocking resources above fold

### 6. Code Quality

- [ ] Components single-responsibility
- [ ] Event handlers properly named (handle*, on*)
- [ ] No magic numbers (use constants)
- [ ] Loading/error states handled
- [ ] Props destructured with defaults

### 7. OpenAPI Adherence

- [ ] API types from `typescript-swagger-api` generated client
- [ ] Request/response types match OpenAPI spec
- [ ] Error responses handled according to spec

## Output Format

```markdown
# Frontend Review: [file/component]

## Summary

Overall: ✅ Approved | ⚠️ Needs Changes | ❌ Major Issues

## Findings

### ✅ Good

- Semantic HTML structure
- Proper TypeScript types
- DaisyUI components used correctly

### ⚠️ Suggestions

- Consider adding aria-label to icon button (line 45)
- Touch target slightly small on mobile (line 78)

### ❌ Must Fix

- Missing alt text on hero image (line 23)
- Using `any` type (line 56)
- Hardcoded hex color in className (line 34)

## Recommendations

1. Add `aria-label="Close dialog"` to close button
2. Replace `any` with proper type from API client
3. Use `text-base-content` instead of `text-[#333]`
```

## Common Issues Quick Reference

| Issue                       | Fix                                    |
| --------------------------- | -------------------------------------- |
| `className="text-[#fff]"`   | Use `text-base-content` or theme color |
| `className="bg-[var(--x)]"` | Use DaisyUI class like `bg-primary`    |
| `type Props = any`          | Define proper interface                |
| `onClick` on div            | Use `button` element                   |
| Inline nested interface     | Extract to separate interface          |
| Direct union type           | Use const types pattern                |
