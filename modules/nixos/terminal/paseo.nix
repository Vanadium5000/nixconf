{ inputs, self, ... }:
{
  flake.nixosModules.paseo =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs.paseo;
      inherit (lib) mkEnableOption mkIf;

      user = config.preferences.user.username;
      homeDirectory = config.preferences.paths.homeDirectory;
      system = pkgs.stdenv.hostPlatform.system;
      paseoPackage = self.packages.${system}.paseo;
      ompPackage = inputs.llm-agents.packages.${system}.omp;

      paseoHome = "${homeDirectory}/.paseo";
      paseoCache = "${homeDirectory}/.cache/paseo";
      paseoSocket = "${paseoHome}/paseo.sock";

      shellUser = lib.escapeShellArg user;
      shellPaseoHome = lib.escapeShellArg paseoHome;
      shellPaseoCache = lib.escapeShellArg paseoCache;

      paseoPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "paseo";
        targetFile = paseoHome;
        isDirectory = true;
      };
    in
    {
      options.programs.paseo.enable = mkEnableOption "Paseo package and mutable state persistence";

      config = mkIf cfg.enable {
        # Paseo stores daemon identity, provider overrides, agent records,
        # project registries, chat rooms, loops, schedules, local speech models,
        # and optional worktree roots under PASEO_HOME; persist it as one tree so
        # first-run daemon writes cannot race a collection of file units.
        # Sources: @getpaseo/server paseo-home.js and config.js in llm-agents input.
        system.activationScripts.paseo-user-files = {
          text = ''
            install -d -m 0700 -o ${shellUser} -g users ${shellPaseoHome}
            install -d -m 0700 -o ${shellUser} -g users ${shellPaseoHome}/agents
            install -d -m 0700 -o ${shellUser} -g users ${shellPaseoHome}/chat
            install -d -m 0700 -o ${shellUser} -g users ${shellPaseoHome}/loops
            install -d -m 0700 -o ${shellUser} -g users ${shellPaseoHome}/projects
            install -d -m 0700 -o ${shellUser} -g users ${shellPaseoHome}/schedules
            install -d -m 0700 -o ${shellUser} -g users ${shellPaseoCache}

            config_file=${shellPaseoHome}/config.json
            if [ ! -e "$config_file" ]; then
              printf '{"version":1,"agents":{"providers":{"pi":{"command":["%s"],"env":{"PI_CODING_AGENT_DIR":"%s/.omp/agent"}}}},"daemon":{"listen":"%s","mcp":{"injectIntoAgents":true}}}\n' \
                ${lib.escapeShellArg "${ompPackage}/bin/omp"} \
                ${lib.escapeShellArg homeDirectory} \
                ${lib.escapeShellArg paseoSocket} > "$config_file"
            else
              tmp="$(${pkgs.coreutils}/bin/mktemp)"
              ${pkgs.jq}/bin/jq \
                --arg omp ${lib.escapeShellArg "${ompPackage}/bin/omp"} \
                --arg piDir ${lib.escapeShellArg "${homeDirectory}/.omp/agent"} \
                --arg listen ${lib.escapeShellArg paseoSocket} \
                '.version = (.version // 1)
                 | .agents.providers.pi.command = [$omp]
                 | .agents.providers.pi.env.PI_CODING_AGENT_DIR = $piDir
                 | .daemon.listen = $listen
                 | .daemon.mcp.injectIntoAgents = (.daemon.mcp.injectIntoAgents // true)' \
                "$config_file" > "$tmp"
              install -m 0600 -o ${shellUser} -g users "$tmp" "$config_file"
              rm -f "$tmp"
            fi

            chmod 0600 "$config_file"
            chown ${shellUser}:users "$config_file"
          '';
          deps = [ "users" ];
        };

        system.activationScripts.paseo-persistence = {
          text = paseoPersistence.activationScript;
          deps = [ "users" ];
        };

        fileSystems = paseoPersistence.fileSystems;

        environment.systemPackages = [ paseoPackage ];
      };
    };
}
