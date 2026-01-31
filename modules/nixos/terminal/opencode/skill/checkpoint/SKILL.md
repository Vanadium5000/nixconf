---
name: checkpoint
description: Save progress snapshot during long tasks
---

# Checkpoint Skill

Create a progress snapshot that can be reviewed later or used for recovery.

## Invocation

`/checkpoint [optional message]`

## Behavior

1. Read current TODO list state
2. Get recently modified files via `git status`
3. Append checkpoint to PROGRESS.md:

```markdown
---

## 📍 Checkpoint: [timestamp]

**Message**: [user message or "Auto-checkpoint"]

### Completed Since Last Checkpoint

- [x] Task 1 - Brief description
- [x] Task 2 - Brief description

### Currently In Progress

- [ ] Task 3 - What's being worked on

### Remaining

- [ ] Task 4
- [ ] Task 5

### Files Modified (since last checkpoint)

- path/to/new-file.ts (added)
- path/to/modified-file.nix (modified)

### Observations

- Any patterns noticed
- Decisions made and rationale
- Potential issues ahead

---
```

## Auto-Checkpoint Triggers

During `/afk-task`, automatically create checkpoints:

- Every 10 completed subtasks
- Before any risky operation (large refactor, deletion)
- When switching major phases of work
- If more than 30 minutes since last checkpoint
