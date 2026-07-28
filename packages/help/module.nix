{ self, ... }:
{
  flake.nixosModules.command-help =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        concatMap
        mkEnableOption
        mkIf
        mkOption
        types
        ;
      cfg = config.preferences.commandHelp;
      commandType = types.submodule {
        options = {
          command = mkOption {
            type = types.strMatching "[^[:space:]]+";
            description = "Primary executable or shell alias shown by help.";
          };
          aliases = mkOption {
            type = types.listOf (types.strMatching "[^[:space:]]+");
            default = [ ];
            description = "Additional executable names or shell aliases for this command.";
          };
          description = mkOption {
            type = types.str;
            description = "One-line command purpose rendered by help.";
          };
          usage = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Optional invocation synopsis rendered by help.";
          };
          details = mkOption {
            type = types.lines;
            default = "";
            description = "Optional operational details rendered below the synopsis.";
          };
          package = mkOption {
            type = types.nullOr types.package;
            default = null;
            description = "Package that provides the documented primary command when it is not otherwise installed.";
          };
        };
      };
      commands = lib.sort (left: right: left.command < right.command) cfg.commands;
      invocationNames = concatMap (command: [ command.command ] ++ command.aliases) commands;
      duplicateNames = lib.filter (name: lib.count (candidate: candidate == name) invocationNames > 1) (
        lib.unique invocationNames
      );
      document = {
        version = 1;
        commands = map (command: {
          inherit (command)
            command
            aliases
            description
            details
            ;
          usage = if command.usage == null then "" else command.usage;
        }) commands;
      };
      commandPackages = lib.filter (package: package != null) (map (command: command.package) commands);
    in
    {
      options.preferences.commandHelp = {
        enable = mkEnableOption "the generated Nixconf command help index" // {
          default = true;
        };
        commands = mkOption {
          type = types.listOf commandType;
          default = [ ];
          description = "Commands registered by enabled Nixconf packages and modules.";
        };
      };

      config = mkIf cfg.enable {
        assertions = [
          {
            assertion = duplicateNames == [ ];
            message = "preferences.commandHelp.commands has duplicate command or alias names: ${lib.concatStringsSep ", " duplicateNames}";
          }
        ];

        environment.systemPackages = lib.unique (
          [ self.packages.${pkgs.stdenv.hostPlatform.system}.help ] ++ commandPackages
        );
        environment.variables.NIXCONF_HELP_DOCS = "/etc/nixconf/help.json";
        environment.etc."nixconf/help.json".text = builtins.toJSON document;
        preferences.zsh.aliases.h = "help";
        preferences.commandHelp.commands = [
          {
            command = "help";
            aliases = [ "h" ];
            description = "Show documented Nixconf commands enabled on this host.";
            usage = "help [--plain] [--pager] [--docs FILE | --docs-json JSON]";
            details = "Use --plain for logs or pipes, and --pager for an interactive less view.";
          }
        ];
      };
    };
}
