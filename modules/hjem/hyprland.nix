{
  self,
  ...
}:
let
  inherit (self.lib.generators) toHyprconf;
in
{
  flake.nixosModules.extra_hjem =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkOption
        mkIf
        concatLines
        mapAttrsToList
        getExe
        mkAfter
        types
        ;
      user = config.preferences.user.username;
      cfg = config.home.programs.hyprland;

      # Generate a flat list of keybinds with descriptions for the help overlay
      flattenKeybinds =
        prefix: keymap:
        builtins.concatLists (
          mapAttrsToList (
            keyName: keyOptions:
            let
              fullKey = if prefix == "" then keyName else "${prefix} → ${keyName}";
            in
            if builtins.hasAttr "exec" keyOptions || builtins.hasAttr "package" keyOptions then
              [
                {
                  key = fullKey;
                  description = keyOptions.description or "No description";
                  hasExec = builtins.hasAttr "exec" keyOptions;
                }
              ]
            else
              flattenKeybinds fullKey keyOptions
          ) keymap
        );

      # Combine keybinds from preferences.keymap AND keybindDescriptions
      allKeybinds =
        (flattenKeybinds "" config.preferences.keymap)
        ++ (map (kb: {
          key = kb.key;
          description = kb.description;
          category = kb.category or "General";
        }) cfg.keybindDescriptions);

      keybindsJson = builtins.toJSON allKeybinds;
    in
    {
      options.home.programs.hyprland = {
        enable = mkEnableOption "hyprland configuration";

        settings = mkOption {
          default = { };
          description = ''
            hyprland configuration
          '';
        };

        extraConfig = mkOption {
          default = "";
          description = ''
            hyprland configuration string
          '';
        };

        finalConfig = mkOption {
          default = "";
        };

        keybindDescriptions = mkOption {
          type = types.listOf (types.submodule {
            options = {
              key = mkOption {
                type = types.str;
                description = "Keybind (e.g., 'SUPER + Q')";
              };
              description = mkOption {
                type = types.str;
                description = "Human-readable description";
              };
              category = mkOption {
                type = types.str;
                default = "General";
                description = "Category for grouping in help display";
              };
            };
          });
          default = [ ];
          description = "List of keybind descriptions for the help overlay";
        };
      };

      config = mkIf cfg.enable {
        home.programs.hyprland.finalConfig = (toHyprconf { attrs = cfg.settings; }) + cfg.extraConfig;

        hjem.users.${user} = {
          files.".config/hypr/hyprland.conf".text = cfg.finalConfig;
          # Generate keybinds JSON for the help overlay
          files.".config/hypr/keybinds.json".text = keybindsJson;
        };

        home.programs.hyprland.settings.exec-once = builtins.map (
          entry:
          if (builtins.typeOf entry) == "string" then
            getExe (pkgs.writeShellScriptBin "autostart" entry)
          else
            getExe entry
        ) config.preferences.autostart;

        home.programs.hyprland.extraConfig =
          let
            wrapWriteApplication =
              text:
              getExe (
                pkgs.writeShellApplication {
                  name = "script";
                  text = text;
                }
              );

            # Turns sane looking keymaps into ugly hyprland syntax ones
            # "A" into ",A"
            # "super + d" into "super, d"
            sanitizeKeyName =
              keyName:
              let
                replaced = builtins.replaceStrings [ "+" ] [ "," ] keyName;
              in
              if builtins.match ".*,.*" replaced != null then replaced else "," + replaced;

            makeHyprBinds =
              parentKeyName: keyName: keyOptions:
              let
                finalKeyName = sanitizeKeyName keyName;

                submapname =
                  parentKeyName
                  + (builtins.replaceStrings [ " " "," "$" "+" ] [ "hypr" "submaps" "syntax" "suck" ] finalKeyName);
              in
              if builtins.hasAttr "exec" keyOptions then
                ''
                  bind = ${finalKeyName}, exec, ${wrapWriteApplication keyOptions.exec}
                  bind = ${finalKeyName},submap,reset
                ''
              else if builtins.hasAttr "package" keyOptions then
                ''
                  bind = ${finalKeyName}, exec, ${getExe keyOptions.package}
                  bind = ${finalKeyName},submap,reset
                ''
              else
                ''
                  bind = ${finalKeyName}, submap, ${submapname}

                  submap = ${submapname}
                  ${concatLines (mapAttrsToList (makeHyprBinds submapname) keyOptions)}
                  submap = reset
                '';
          in
          mkAfter (concatLines (mapAttrsToList (makeHyprBinds "root") config.preferences.keymap));
      };
    };
}
