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
    # "opencode-rules@latest" # Replaced by kdcokenny/opencode-workspace
    # "opencode-handoff@latest" # Replaced by kdcokenny/opencode-workspace

    # === PLANNING ===
    "@plannotator/opencode@latest" # Visual plan annotation, approval workflow, hard enforcement

    # === NOTIFICATIONS & OBSERVABILITY ===
    "@mohak34/opencode-notifier@latest" # Desktop/Slack/Discord notifications
    # "opencode-helicone-session@latest" # Removed: Not using Helicone for observability

    # === SAFETY ===
    # "cc-safety-net@latest" # Removed: Git checkpoints before destructive operations. Hardcoded, and I manually approve commands anyway.

    # === ORCHESTRATION & BUNDLE ===
    "kdcokenny/opencode-workspace" # Bundled multi-agent orchestration harness (planning, delegation, rules, etc.)
  ];
}
