{
  plugins = [
    "oh-my-opencode-slim" # Slim agent harness; config lives in oh-my-opencode-slim.jsonc and TUI registration lives in tui.json.
    # "@plannotator/opencode" # Visual plan annotation, approval workflow, hard enforcement
    "opencode-devcontainers" # Run multiple devcontainer instances with auto-assigned ports for OpenCode
    "@tarquinen/opencode-dcp"
  ];
}
