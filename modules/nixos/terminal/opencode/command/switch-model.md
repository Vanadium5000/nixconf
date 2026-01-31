---
description: Switch between AI models (opus/gemini-pro) for expensive agents
---

# Switch Model

Switch the AI model used for expensive agents (build, plan, advisor).

## Usage

- `/switch-model` or `/switch-model status` - Show current model
- `/switch-model opus` - Switch to Claude Opus 4.5 Thinking
- `/switch-model gemini` or `/switch-model pro` - Switch to Gemini 3 Pro Preview

## Instructions

When this command is invoked, load the `switch-model` skill using the skill
tool, then execute the requested action.

The command arguments are: **$ARGUMENTS**

If no arguments provided, show the current model status.
