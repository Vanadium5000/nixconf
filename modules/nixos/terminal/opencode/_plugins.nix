# Plugin list for OpenCode
# Modular setup - each plugin has a single purpose
{
  plugins = [
    "oh-my-openagent@latest" # Upstream agent bundle; project config narrows its defaults for this repo
    # "@plannotator/opencode@latest" # Visual plan annotation, approval workflow, hard enforcement
    "opencode-devcontainers@latest" # Run multiple devcontainer instances with auto-assigned ports for OpenCode
    # "opencode-mem" # Persistent memory using local vector database
  ];
}
