# Plugin list for OpenCode
# Modular setup - each plugin has a single purpose
#
# NOTE: ralph-wiggum is a CLI tool, NOT a plugin. Install globally:
#   npm install -g @th0rgal/ralph-wiggum
# Then use: ralph "prompt" --max-iterations 10
{
  plugins = [
    "oh-my-opencode" # Upstream agent bundle; project config narrows its defaults for this repo
    "@plannotator/opencode@latest" # Visual plan annotation, approval workflow, hard enforcement
    # "opencode-mem" # Persistent memory using local vector database
  ];
}
