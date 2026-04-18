{
  user,
  configFile,
  initialConfig,
  ohMyOpencodeConfig,
  opencodeMemConfig,
  ...
}:
{
  ${user} = {
    files = {
      "${configFile}" = {
        text = builtins.toJSON initialConfig;
        type = "copy";
        permissions = "0600";
      };

      ".config/opencode/oh-my-opencode.jsonc" = {
        text = builtins.toJSON ohMyOpencodeConfig;
        type = "copy";
        permissions = "0600";
      };

      # Compatibility alias used by some OpenCode plugin/runtime paths.
      # Keep this synced with oh-my-opencode.jsonc to avoid stale model picks.
      ".config/opencode/oh-my-openagent.jsonc" = {
        text = builtins.toJSON ohMyOpencodeConfig;
        type = "copy";
        permissions = "0600";
      };

      ".config/opencode/skill" = {
        source = ./skill;
        type = "copy";
        permissions = "0755";
      };
      ".config/opencode/command" = {
        source = ./command;
        type = "copy";
        permissions = "0755";
      };
      ".config/opencode/plugin" = {
        source = ./plugin;
        type = "copy";
        permissions = "0755";
      };
      ".config/opencode/AGENTS.md" = {
        source = ./_AGENTS.md;
        type = "copy";
        permissions = "0644";
      };
      ".config/opencode/package.json" = {
        source = ./_package.json;
        type = "copy";
        permissions = "0644";
      };
      ".config/opencode/opencode-mem.jsonc" = {
        text = builtins.toJSON opencodeMemConfig;
        type = "copy";
        permissions = "0644";
      };
    };
  };
}
