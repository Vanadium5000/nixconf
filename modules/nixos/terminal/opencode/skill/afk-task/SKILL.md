---
name: afk-task
description: Execute long-running tasks with progress tracking for AFK sessions
---

# AFK Task Execution Skill

Use this skill when executing extended tasks autonomously while the user is away.

## Invocation

`/afk-task [task description]`

## Setup Phase

1. Create `PROGRESS.md` in project root:

   ```markdown
   # AFK Task: [description]

   Started: [ISO timestamp]
   Status: 🔄 In Progress

   ## Progress Log
   ```

2. Create comprehensive TODO list for all subtasks
3. Send notification: "AFK task started: [description]"

## Execution Phase

For each subtask:

1. Mark task as `in_progress` in TODO
2. Execute the work
3. Append to PROGRESS.md:

   ```markdown
   ### [HH:MM] Task Name

   **Status**: ✅ Complete | ❌ Failed | ⏭️ Skipped
   **Files**: file1.ts, file2.nix
   **Details**: What was done or why it failed
   ```

4. Mark task complete/failed in TODO
5. Continue to next task

## Error Handling Protocol

On error:

1. Log full error to PROGRESS.md
2. Attempt recovery (retry with different approach)
3. If 3 attempts fail:
   - Create/append to `BLOCKERS.md`:

     ```markdown
     ## Blocker: [task name]

     **Time**: [timestamp]
     **Error**: [full error message]
     **Attempts**:

     1. [what was tried]
     2. [alternative approach]
     3. [final attempt]

     **Requires**: User intervention, dependency, etc.
     ```

   - Skip task and continue
   - Send notification: "⚠️ Blocker encountered - see BLOCKERS.md"

## Completion Phase

1. Delegate to `verifier` agent for all changes
2. Create `SUMMARY.md`:

   ```markdown
   # Task Summary: [description]

   | Metric    | Value     |
   | --------- | --------- |
   | Started   | [time]    |
   | Completed | [time]    |
   | Duration  | [minutes] |

   ## Results

   - ✅ Completed: X tasks
   - ❌ Failed: Y tasks
   - ⏭️ Skipped: Z tasks

   ## Files Modified

   - path/to/file1.ts
   - path/to/file2.nix

   ## Verification

   [output from verifier agent]

   ## Blockers (if any)

   See BLOCKERS.md
   ```

3. Update PROGRESS.md status to "✅ Complete" or "⚠️ Complete with issues"
4. Send notification: "✅ AFK task complete - see SUMMARY.md"

## Critical Rules

- **NEVER** fail silently - always log everything
- Update PROGRESS.md after **EVERY** subtask
- If stuck for more than 5 minutes on one task, document and move on
- Always run verification at the end
- Send notifications for: start, blockers, completion
