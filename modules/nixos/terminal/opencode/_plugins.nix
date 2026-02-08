# Plugin list for OpenCode
# Modular setup - each plugin has a single purpose
#
# NOTE: ralph-wiggum is a CLI tool, NOT a plugin. Install globally:
#   npm install -g @th0rgal/ralph-wiggum
# Then use: ralph "prompt" --max-iterations 10
{
  plugins = [
    # === CONTEXT & MODEL GUIDANCE ===
    # DCP seems to give the AIs debilitating dementia
    # "@tarquinen/opencode-dcp@latest" # Dynamic Context Pruning - essential for long sessions
    "opencode-rules@latest" # Injects AGENTS.md into system prompt
    "opencode-handoff@latest" # Session continuity for multi-agent handoffs

    # === PLANNING ===
    "@plannotator/opencode@latest" # Visual plan annotation, approval workflow, hard enforcement

    # === MEMORY ===
    "opencode-agent-memory@latest" # Letta-style persistent memory blocks

    # === NOTIFICATIONS & OBSERVABILITY ===
    "@mohak34/opencode-notifier@latest" # Desktop/Slack/Discord notifications
    "opencode-helicone-session@latest" # LLM observability via Helicone

    # === SAFETY ===
    "cc-safety-net@latest" # Git checkpoints before destructive operations
  ];
}
