# Plugin list for OpenCode
# Replaces oh-my-opencode with focused, single-purpose plugins
{
  plugins = [
    "@paulp-o/opencode-background-agent@latest" # Async parallel task delegation
    "opencode-ralph-loop@latest" # Auto-continue loop until task completion (minimal, no spam)
    "@mohak34/opencode-notifier@latest" # Desktop notifications
    "opencode-todo-reminder@latest" # Todo continuation and auto-submit
    "@tarquinen/opencode-dcp@latest" # Context trimming (Dynamic Context Pruning)
    "opencode-type-inject@latest" # Type injection for file reads
    "opencode-wakatime@latest" # Time tracking
    "opencode-helicone-session@latest" # LLM observability
  ];
}
