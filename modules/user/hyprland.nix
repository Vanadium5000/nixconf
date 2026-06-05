{
  self,
  ...
}:
let
  inherit (self.lib.generators) toHyprconf;
in
{
  flake.nixosModules.user-hyprland-config =
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
        concatMapStringsSep
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

      luaString = builtins.toJSON;

      luaKeyName =
        keyName:
        let
          parts = lib.splitString "," keyName;
          hasHyprlangSeparator = builtins.length parts > 1;
          modPart = lib.trim (builtins.head parts);
          keyPart = lib.trim (builtins.concatStringsSep "," (builtins.tail parts));
          luaMods = lib.trim (builtins.replaceStrings [ "_" " " ] [ " + " " + " ] modPart);
        in
        if !hasHyprlangSeparator then
          builtins.replaceStrings [ "_" ] [ " + " ] keyName
        else if luaMods == "" then
          keyPart
        else
          "${luaMods} + ${keyPart}";

      luaExec = command: "hl.dsp.exec_cmd(${luaString command})";

      luaPreferenceKeymap =
        let
          wrapWriteApplication =
            text:
            getExe (
              pkgs.writeShellApplication {
                name = "script";
                text = text;
              }
            );

          makeLuaBinds =
            parentKeyName: keyName: keyOptions:
            let
              finalKeyName = luaKeyName keyName;
              submapname =
                parentKeyName
                + (builtins.replaceStrings [ " " "," "$" "+" ] [ "hypr" "submaps" "syntax" "suck" ] keyName);
            in
            if keyOptions ? exec && keyOptions.exec != null then
              ''
                hl.bind(${luaString finalKeyName}, ${luaExec (wrapWriteApplication keyOptions.exec)})
                hl.bind(${luaString finalKeyName}, hl.dsp.submap("reset"))
              ''
            else if keyOptions ? package && keyOptions.package != null then
              ''
                hl.bind(${luaString finalKeyName}, ${luaExec (getExe keyOptions.package)})
                hl.bind(${luaString finalKeyName}, hl.dsp.submap("reset"))
              ''
            else
              ''
                hl.bind(${luaString finalKeyName}, hl.dsp.submap(${luaString submapname}))
                hl.define_submap(${luaString submapname}, function()
                ${concatLines (mapAttrsToList (makeLuaBinds submapname) keyOptions)}
                end)
              '';
        in
        concatLines (mapAttrsToList (makeLuaBinds "root") config.preferences.keymap);

      luaAutostart = ''
        hl.on("hyprland.start", function()
        ${concatMapStringsSep "\n" (
          entry:
          let
            command = if (builtins.typeOf entry) == "string" then entry else getExe entry;
          in
          "hl.exec_cmd(${luaString command})"
        ) config.preferences.autostart}
        end)
      '';
    in
    {
      options.home.programs.hyprland = {
        enable = mkEnableOption "hyprland configuration";

        configType = mkOption {
          type = types.enum [
            "hyprlang"
            "lua"
          ];
          default = "hyprlang";
          description = "Hyprland configuration language to write.";
        };

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

        luaConfig = mkOption {
          type = types.lines;
          default = "";
          description = "Hyprland Lua configuration body written to hyprland.lua.";
        };

        extraLuaConfig = mkOption {
          type = types.lines;
          default = "";
          description = "Extra Hyprland Lua configuration appended after luaConfig.";
        };

        finalConfig = mkOption {
          default = "";
        };

        finalLuaConfig = mkOption {
          default = "";
        };

        keybindDescriptions = mkOption {
          type = types.listOf (
            types.submodule {
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
            }
          );
          default = [ ];
          description = "List of keybind descriptions for the help overlay";
        };
      };

      config = mkIf cfg.enable {
        home.programs.hyprland.finalConfig = (toHyprconf { attrs = cfg.settings; }) + cfg.extraConfig;
        home.programs.hyprland.finalLuaConfig = concatLines [
          cfg.luaConfig
          luaAutostart
          cfg.extraLuaConfig
          luaPreferenceKeymap
        ];

        system.activationScripts.hyprland-user-files = {
          text =
            (
              if cfg.configType == "lua" then
                ''
                  rm -f ${lib.escapeShellArg "${config.preferences.paths.homeDirectory}/.config/hypr/hyprland.conf"}
                ''
              else
                ''
                  rm -f ${lib.escapeShellArg "${config.preferences.paths.homeDirectory}/.config/hypr/hyprland.lua"}
                ''
            )
            + self.lib.userFiles.mkActivationScript {
              inherit user;
              inherit pkgs;
              homeDirectory = config.preferences.paths.homeDirectory;
              files =
                (
                  if cfg.configType == "lua" then
                    {
                      ".config/hypr/hyprland.lua".text = cfg.finalLuaConfig;
                    }
                  else
                    {
                      ".config/hypr/hyprland.conf".text = cfg.finalConfig;
                    }
                )
                // {
                  # Generate keybinds JSON for the help overlay
                  ".config/hypr/keybinds.json".text = keybindsJson;
                };
            };
          deps = [ "users" ];
        };

        home.programs.hyprland.settings.exec-once = lib.mkIf (cfg.configType == "hyprlang") (
          builtins.map (
            entry:
            if (builtins.typeOf entry) == "string" then
              getExe (pkgs.writeShellScriptBin "autostart" entry)
            else
              getExe entry
          ) config.preferences.autostart
        );

        home.programs.hyprland.extraConfig = lib.mkIf (cfg.configType == "hyprlang") (
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
          mkAfter (concatLines (mapAttrsToList (makeHyprBinds "root") config.preferences.keymap))
        );
      };
    };
}
