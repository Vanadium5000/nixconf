---
description: Create a structured plan for a task, saved to .opencode/plans/ for review
---

# Plan Creation

Create a comprehensive implementation plan for the user's request.

## Instructions

1. **Analyze the request**: Understand what the user wants to achieve
2. **Research the codebase**: Read relevant files to understand current state
3. **Create a structured plan** following the format below
4. **Save the plan** to `.opencode/plans/<slug>.md`
5. **Update state** in `.opencode/plans/state.json`
6. **Submit for review** via plannotator or plan-reviewer agent

## Plan File Format

Save to `.opencode/plans/<slug>.md`:

```markdown
---
id: <slug>
title: <human-readable title>
created: <ISO timestamp>
status: pending_review
reviewed_by: null
approved_at: null
---

# <Title>

## Goal

<What the user wants to achieve>

## Tasks

### T1: <Task title>

- **File(s)**: `path/to/file.ts`
- **Dependencies**: None
- **Description**: <What to do>
- **Outcome**: <What success looks like>
- **Verification**: <How to confirm completion>

### T2: <Task title>

- **File(s)**: `path/to/another.ts`
- **Dependencies**: T1
- **Description**: <What to do>
- **Outcome**: <What success looks like>
- **Verification**: <How to confirm completion>

## Risks

- <Risk 1 and mitigation>
- <Risk 2 and mitigation>

## Assumptions

- <Assumption 1>
- <Assumption 2>
```

## State File Format

Update `.opencode/plans/state.json`:

```json
{
  "plans": {
    "<slug>": {
      "status": "pending_review",
      "created": "<ISO timestamp>",
      "reviewed_by": null,
      "approved_at": null,
      "tasks_completed": 0,
      "tasks_total": <N>
    }
  },
  "active_plan": "<slug>"
}
```

## After Creating Plan

1. If plannotator plugin is available, call `submit_plan` tool to open visual review UI
2. Otherwise, delegate to `plan-reviewer` agent for text-based review
3. Inform the user that the plan requires review before execution

## Status Values

| Status           | Meaning                                    |
| ---------------- | ------------------------------------------ |
| `pending_review` | Plan created, awaiting review              |
| `approved`       | Reviewed and approved, ready for execution |
| `rejected`       | Reviewer found critical issues             |
| `in_progress`    | Currently being executed                   |
| `completed`      | All tasks finished                         |
| `abandoned`      | User cancelled the plan                    |

---

**User's request:** $ARGUMENTS
