{
  inputs,
  lib,
  self,
  ...
}:
let
  inherit (lib)
    all
    concatMapStringsSep
    escapeShellArg
    literalExpression
    mapAttrs'
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    types
    ;

  gitLib = self.lib.git;

  identityType = types.submodule (
    { name, ... }:
    {
      options = {
        id = mkOption {
          internal = true;
          type = types.str;
          default = name;
          description = "Git identity key.";
        };

        name = mkOption {
          type = types.str;
          description = "Git author and committer name.";
        };

        email = mkOption {
          type = types.str;
          description = "Git author and committer email address.";
        };

        signingKey = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional git signing key written as user.signingKey.";
        };

        gpgFormat = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "ssh";
          description = "Optional gpg.format value used with signingKey.";
        };

        signByDefault = mkEnableOption "commit signing by default for this identity";

        extraConfig = mkOption {
          type = types.attrs;
          default = { };
          example = literalExpression ''
            {
              commit.template = "~/.config/git/templates/work-commit-message";
            }
          '';
          description = "Additional git config sections merged into this identity snippet.";
        };
      };
    }
  );

  includeType = types.submodule {
    options = {
      condition = mkOption {
        type = types.str;
        example = "gitdir:~/src/work/";
        description = "Git includeIf condition without the surrounding includeIf keyword.";
      };

      identity = mkOption {
        type = types.str;
        description = "Key from preferences.git.identities to include when condition matches.";
      };
    };
  };

  renderConditionalInclude = include: ''
    [includeIf "${gitLib.escapeGitString include.condition}"]
      path = "~/.config/git/identities/${gitLib.escapeGitString include.identity}.gitconfig"
  '';

  mkMainGitConfig =
    cfg:
    let
      strictConfig = gitLib.renderConfigAttrs { user.useConfigOnly = cfg.strict; };
      mutableIncludes = ''
        [include]
          path = "~/.config/git/common.gitconfig"
      '';
      identityIncludes = concatMapStringsSep "\n" renderConditionalInclude cfg.includes;
    in
    concatMapStringsSep "\n" (part: part) [
      strictConfig
      mutableIncludes
      identityIncludes
    ];

  mkIdentityFiles =
    cfg:
    let
      renderIdentityPair = identity: ''
        [user]
          name = "${gitLib.escapeGitString identity.name}"
          email = "${gitLib.escapeGitString identity.email}"
      '';
    in
    (mapAttrs' (
      name: identity:
      nameValuePair ".config/git/identities/${name}.gitconfig" {
        text = gitLib.mkIdentityConfig identity;
        type = "copy";
        permissions = "0644";
      }
    ) cfg.identities)
    // (mapAttrs' (
      name: identity:
      nameValuePair ".config/git/identity-manager/identities/${name}.gitconfig" {
        text = renderIdentityPair identity;
        type = "copy";
        clobber = false;
        permissions = "0644";
      }
    ) cfg.identities);

  mkHelper =
    pkgs:
    let
      script = builtins.readFile ./git-identity.sh;
      substituted =
        builtins.replaceStrings
          [
            "@git@"
            "@gum@"
          ]
          [
            (escapeShellArg "${pkgs.git}/bin/git")
            (escapeShellArg "${pkgs.gum}/bin/gum")
          ]
          script;
    in
    pkgs.writeShellScriptBin "git-identity" substituted;
in
{
  flake.nixosModules.git =
    {
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.preferences.git;
    in
    {
      options.preferences.git = {
        strict = mkEnableOption "Git user.useConfigOnly so unclassified repositories cannot commit" // {
          default = true;
        };

        defaultIdentity = mkOption {
          type = types.str;
          default = "personal";
          description = "Identity used for default project include rules.";
        };

        identities = mkOption {
          type = types.attrsOf identityType;
          default = { };
          description = "Named Git identities rendered under ~/.config/git/identities.";
        };

        includes = mkOption {
          type = types.listOf includeType;
          default = [ ];
          description = "Conditional identity includes rendered into ~/.gitconfig.";
        };

        commonConfig = mkOption {
          type = types.attrs;
          default = { };
          description = "Non-identity Git config rendered into ~/.config/git/common.gitconfig.";
        };
      };

      config = mkIf config.preferences.enable {
        assertions = [
          {
            assertion = builtins.hasAttr cfg.defaultIdentity cfg.identities;
            message = "preferences.git.defaultIdentity must name an entry in preferences.git.identities.";
          }
          {
            assertion = all (include: builtins.hasAttr include.identity cfg.identities) cfg.includes;
            message = "Every preferences.git.includes entry must reference an entry in preferences.git.identities.";
          }
        ];

        preferences.git = {
          identities = {
            personal = {
              name = mkDefault cfg.username;
              email = mkDefault cfg.email;
              extraConfig.user.useConfigOnly = true;
            };

            password-store = {
              name = mkDefault cfg.username;
              email = mkDefault cfg.email;
              extraConfig.user.useConfigOnly = true;
            };

            bot = {
              name = mkDefault "nixconf git automation";
              email = mkDefault "git-automation@${config.preferences.hostName}.local";
              extraConfig.user.useConfigOnly = true;
            };
          };

          includes = [
            {
              condition = "gitdir:${config.preferences.paths.configDirectory}/";
              identity = cfg.defaultIdentity;
            }
            {
              condition = "gitdir:${config.preferences.paths.homeDirectory}/.local/share/password-store/";
              identity = "password-store";
            }
          ];

          commonConfig = {
            init.defaultBranch = "main";
            pull.ff = "only";
          };
        };

        system.activationScripts.git-user-config = {
          text = self.lib.userFiles.mkActivationScript {
            user = config.preferences.user.username;
            inherit pkgs;
            homeDirectory = config.preferences.paths.homeDirectory;
            files = {
              ".gitconfig" = {
                text = mkMainGitConfig cfg;
                type = "copy";
                permissions = "0644";
              };

              ".config/git/common.gitconfig" = {
                text = gitLib.renderConfigAttrs cfg.commonConfig;
                type = "copy";
                permissions = "0644";
              };
            }
            // mkIdentityFiles cfg;
          };
          deps = [ "users" ];
        };

        impermanence.home.directories = [ ".config/git/identity-manager" ];

        environment.systemPackages = [ (mkHelper pkgs) ];
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      packages.git = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.git;
      };

      packages.git-identity = mkHelper pkgs;
    };
}
