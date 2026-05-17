# Plugin list for OpenCode
# Modular setup - each plugin has a single purpose
# "rm -rf ~/.cache/opencode/packages/" is a hacky but working way to update plugins once installed
{
  plugins = [
    "oh-my-openagent" # Upstream agent bundle; project config narrows its defaults for this repo
    # "@plannotator/opencode" # Visual plan annotation, approval workflow, hard enforcement
    "opencode-devcontainers" # Run multiple devcontainer instances with auto-assigned ports for OpenCode
    "opencode-pty" # OpenCode plugin for interactive PTY management - run background processes, send input, read output with regex filtering
    "@tarquinen/opencode-dcp"
  ];
}
