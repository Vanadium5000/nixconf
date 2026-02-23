# Plugin list for OpenCode
# Modular setup - each plugin has a single purpose
#
# NOTE: ralph-wiggum is a CLI tool, NOT a plugin. Install globally:
#   npm install -g @th0rgal/ralph-wiggum
# Then use: ralph "prompt" --max-iterations 10
{
  plugins = [
    # === PLANNING ===
    "@plannotator/opencode@latest" # Visual plan annotation, approval workflow, hard enforcement

    # === NOTIFICATIONS & OBSERVABILITY ===
    "@mohak34/opencode-notifier@latest" # Desktop notifications
    # "opencode-helicone-session@latest" # Removed: Not using Helicone for observability

    # === SAFETY ===
    # "cc-safety-net@latest" # Removed: Git checkpoints before destructive operations. Hardcoded, and I manually approve commands anyway.

    # === ORCHESTRATION & BUNDLE ===
    "@tarquinen/opencode-dcp@1.2.7" # Dynamic Context Pruning - essential for long sessions
    "@franlol/opencode-md-table-formatter"
    "opencode-ralph-loop"
    "opencode-todo-reminder"
    "opencode-snippets"
  ];
}
