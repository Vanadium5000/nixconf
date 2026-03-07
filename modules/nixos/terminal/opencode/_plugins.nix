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

    # === SAFETY ===
    # "cc-safety-net@latest" # Removed: Git checkpoints before destructive operations.

    # === ORCHESTRATION & BUNDLE ===
    "@tarquinen/opencode-dcp@1.2.7" # Dynamic Context Pruning - essential for long sessions
    "@franlol/opencode-md-table-formatter" # Format markdown tables
    "opencode-snippets" # Manage codebase snippets
  ];
}
