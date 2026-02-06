---
description: Execute an approved plan - BLOCKS if plan not reviewed
---

# Start Work on Plan

Execute tasks from an approved plan. This command enforces plan review.

## CRITICAL: Review Enforcement

**This command will BLOCK execution if the plan has not been reviewed.**

Before executing ANY task, you MUST:

1. Read `.opencode/plans/state.json`
2. Check the plan's `status` field
3. **REFUSE to proceed** if status is not `approved`

## Pre-Execution Check

```text
IF state.json does not exist:
  ERROR: "No plans found. Use /plan to create one first."

IF plan not found in state.json:
  ERROR: "Plan '<slug>' not found. Available plans: <list>"

IF plan.status == "pending_review":
  ERROR: "Plan '<slug>' requires review before execution.
         Use plannotator UI or delegate to plan-reviewer agent."

IF plan.status == "rejected":
  ERROR: "Plan '<slug>' was rejected. Review feedback and create a new plan."

IF plan.status == "in_progress":
  INFO: "Resuming plan '<slug>' from last checkpoint."

IF plan.status == "approved":
  OK: Proceed with execution
```

## Execution Protocol

1. **Update state**: Set `status: "in_progress"` in state.json
2. **Read the plan**: Load `.opencode/plans/<slug>.md`
3. **Execute tasks in order**: Respect dependencies
4. **Update progress**: Increment `tasks_completed` after each task
5. **Verify each task**: Run the verification step before proceeding
6. **Mark complete**: Set `status: "completed"` when all tasks done

## Task Execution

For each task:

1. Read the task specification from the plan
2. Implement the change as specified
3. Run the verification step
4. Update `tasks_completed` in state.json
5. Proceed to next task (respecting dependencies)

## Error Handling

If a task fails:

1. Log the error with full context
2. Do NOT proceed to dependent tasks
3. Update state.json with error details
4. Inform user of the failure and options:
   - Retry the failed task
   - Skip and continue (user must confirm)
   - Abandon the plan

## Progress Tracking

Keep the user informed:

```text
Executing plan: <title>
Progress: [=====>    ] 3/7 tasks

Current: T4 - Add authentication middleware
Status: In progress...
```

## Arguments

- If no argument: Resume active plan (from `state.json.active_plan`)
- If slug provided: Start/resume that specific plan

---

**Plan to execute:** $ARGUMENTS
