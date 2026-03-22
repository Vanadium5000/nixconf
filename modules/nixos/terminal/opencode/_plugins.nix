# Plugin list for OpenCode
# Modular setup - each plugin has a single purpose
{
  plugins = [
    "oh-my-opencode" # Upstream agent bundle; project config narrows its defaults for this repo
    "@plannotator/opencode@latest" # Visual plan annotation, approval workflow, hard enforcement
    # "opencode-mem" # Persistent memory using local vector database
  ];
}
