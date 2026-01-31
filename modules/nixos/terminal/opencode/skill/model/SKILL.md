---
name: model
description: Switch between AI models (opus/gemini-pro) for expensive agents
---

# Model Switch Skill

This skill provides the `/model` slash command for switching between AI models.

## Commands

### /model status

Show the current model configuration for expensive agents (planner, builder, advisor).

### /model opus

Switch expensive agents to Claude Opus 4.5 Thinking.

- Model ID: `antigravity-claude/claude-opus-4-5-thinking`
- Best for: Complex reasoning, architecture decisions, difficult debugging

### /model gemini (or /model pro)

Switch expensive agents to Gemini 3 Pro Preview.

- Model ID: `antigravity-gemini/gemini-3-pro-preview`
- Best for: General tasks, cost-effective operation

### /model flash

Note: Flash is automatically used for scout and researcher agents.

- Model ID: `antigravity-gemini/gemini-3-flash`
- Cannot be set for expensive agents (planner, builder, advisor)

## How to Execute

When the user invokes `/model <command>`, follow these steps:

### For /model status

1. Read `~/.config/opencode/config.json`
2. Look at the `agents` section
3. Report which model is configured for planner/builder/advisor

### For /model opus or /model gemini

1. Read `~/.config/opencode/config.json`
2. Update the model field for these agents:
   - planner
   - builder
   - advisor
3. Write the updated config back
4. Inform user that changes will take effect on next session start

## Model Mapping

| Category       | Model                                       | Agents                    |
| -------------- | ------------------------------------------- | ------------------------- |
| Heavy (opus)   | antigravity-claude/claude-opus-4-5-thinking | planner, builder, advisor |
| Standard (pro) | antigravity-gemini/gemini-3-pro-preview     | planner, builder, advisor |
| Quick (flash)  | antigravity-gemini/gemini-3-flash           | scout, researcher         |

## Important Notes

- Model changes require restarting OpenCode to take effect
- Scout and Researcher always use Flash for cost efficiency
- The CLI tool `opencode-model` can also be used outside of sessions
