---
name: switch-model
description: Switch between AI models (opus/gemini-pro) for expensive agents
---

# Switch Model Skill

This skill provides the `/switch-model` slash command for switching between
AI models.

## Commands

### /switch-model status

Show the current model configuration for expensive agents (build, plan,
advisor).

### /switch-model opus

Switch expensive agents to Claude Opus 4.5 Thinking.

- Model ID: `antigravity-claude/claude-opus-4-5-thinking`
- Best for: Complex reasoning, architecture decisions, difficult debugging

### /switch-model gemini (or /switch-model pro)

Switch expensive agents to Gemini 3 Pro Preview.

- Model ID: `antigravity-gemini/gemini-3-pro-preview`
- Best for: General tasks, cost-effective operation

### /switch-model flash

Note: Flash is automatically used for scout and researcher agents.

- Model ID: `antigravity-gemini/gemini-3-flash`
- Cannot be set for expensive agents (build, plan, advisor)

## How to Execute

When the user invokes `/switch-model <command>`, follow these steps:

### For /switch-model status

1. Read `~/.config/opencode/config.json`
2. Look at the `agent` section
3. Report which model is configured for build/plan/advisor

### For /switch-model opus or /switch-model gemini

1. Read `~/.config/opencode/config.json`
2. Update the model field for these agents:
   - build
   - plan
   - advisor
3. Write the updated config back
4. Inform user that changes will take effect on next session start

## Model Mapping

| Category       | Model                                       | Agents               |
| -------------- | ------------------------------------------- | -------------------- |
| Heavy (opus)   | antigravity-claude/claude-opus-4-5-thinking | build, plan, advisor |
| Standard (pro) | antigravity-gemini/gemini-3-pro-preview     | build, plan, advisor |
| Quick (flash)  | antigravity-gemini/gemini-3-flash           | scout, researcher    |

## Important Notes

- Model changes require restarting OpenCode to take effect
- Scout and Researcher always use Flash for cost efficiency
- The CLI tool `opencode-model` can also be used outside of sessions
