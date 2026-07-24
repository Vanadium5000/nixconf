{ self, ... }:
{
  flake.nixosModules.kde =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.preferences.kde;
      selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
      user = config.preferences.user.username;
      homeDirectory = config.preferences.paths.homeDirectory;
      persistedHomeDirectory = "/persist/system/${lib.removePrefix "/" homeDirectory}";
      kdeConfigFiles = [
        ".config/baloofilerc"
        ".config/dolphinrc"
        ".config/filetypesrc"
        ".config/kactivitymanagerdrc"
        ".config/kcminputrc"
        ".config/kded6rc"
        ".config/kdeglobals"
        ".config/kglobalshortcutsrc"
        ".config/khotkeysrc"
        ".config/kiorc"
        ".config/kscreenlockerrc"
        ".config/ksmserverrc"
        ".config/ksplashrc"
        ".config/ktimezonedrc"
        ".config/kwalletrc"
        ".config/kwinrc"
        ".config/kwinrulesrc"
        ".config/plasma-localerc"
        ".config/plasma-org.kde.plasma.desktop-appletsrc"
        ".config/plasmanotifyrc"
        ".config/plasmarc"
        ".config/plasmashellrc"
        ".config/powermanagementprofilesrc"
        ".config/spectaclerc"
        ".config/systemsettingsrc"
        ".local/share/user-places.xbel"
      ];
    in
    {
      options.preferences.kde.enable = lib.mkEnableOption "KDE Plasma desktop stack";

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = !config.home.programs.hyprland.enable;
            message = "preferences.kde.enable and home.programs.hyprland.enable are mutually exclusive.";
          }
          {
            assertion = !config.preferences.dankMaterialShell.enable;
            message = "preferences.kde.enable and preferences.dankMaterialShell.enable are mutually exclusive.";
          }
        ];

        services.desktopManager.plasma6.enable = true;

        # Prefer the new Plasma Login Manager when present in nixpkgs 26.05;
        # SDDM remains disabled so two display-manager units cannot compete.
        # Source: nixos/modules/services/display-managers/plasma-login-manager.nix.
        services.displayManager.plasma-login-manager.enable = true;
        services.displayManager.sddm.enable = lib.mkForce false;

        # Keep KDE mutable: only package/runtime integration is declared here.
        # Plasma writes user choices to ~/.config, which is persisted below.
        environment.plasma6.excludePackages = with pkgs.kdePackages; [
          elisa
          konsole
        ];

        environment.systemPackages = [
          pkgs.copyq
          pkgs.pinentry-qt
          pkgs.kdePackages.ksshaskpass
          pkgs.kdePackages.polkit-kde-agent-1
          pkgs.kdePackages.xdg-desktop-portal-kde
          pkgs.kdePackages.kwallet
          pkgs.kdePackages.kwalletmanager
          pkgs.kdePackages.kwallet-pam
          pkgs.kdePackages.kio-admin
          pkgs.kdePackages.kio-extras
          pkgs.kdePackages.partitionmanager
          pkgs.kdePackages.print-manager
          pkgs.kdePackages.spectacle
          pkgs.kdePackages.plasma-browser-integration
          pkgs.kdePackages.plasma-nm
          pkgs.kdePackages.plasma-pa
          selfpkgs.terminal
          selfpkgs.brave-origin
          pkgs.librewolf
          pkgs.brightnessctl
          pkgs.mpc
          pkgs.playerctl
          pkgs.wl-clipboard
          pkgs.unstable.voxtype
          selfpkgs.qs-checklist
          selfpkgs.qs-dmenu
          selfpkgs.qs-emoji
          selfpkgs.qs-keybinds
          selfpkgs.qs-music-local
          selfpkgs.qs-music-search
          selfpkgs.qs-nerd
          selfpkgs.qs-passmenu
          selfpkgs.qs-tools
          selfpkgs.qs-vpn
          selfpkgs.qs-wallpaper
          selfpkgs.toggle-lyrics-overlay
          selfpkgs.toggle-pause-autoclickers
          selfpkgs.stop-autoclickers
          selfpkgs.sound-toggle
          selfpkgs.sound-up
          selfpkgs.sound-down
          selfpkgs.sound-up-small
          selfpkgs.sound-down-small
        ];

        environment.sessionVariables = {
          # Plasma sets KDE_FULL_SESSION itself, but child shells launched by
          # packaged helpers should keep Qt/KDE selection explicit and non-Hyprland.
          XDG_CURRENT_DESKTOP = "KDE";
          XDG_SESSION_DESKTOP = "KDE";
          QT_QPA_PLATFORMTHEME = lib.mkForce "kde";
          QT_QUICK_CONTROLS_STYLE = lib.mkForce "org.kde.desktop";
          SSH_ASKPASS_REQUIRE = "prefer";
        };

        # Plasma's own NixOS module defaults to pinentry-qt/ksshaskpass; keep
        # those choices forced on this profile so GPG and pkexec/SSH prompts use
        # Qt surfaces even if another desktop helper is imported globally.
        programs.gnupg.agent.pinentryPackage = lib.mkForce pkgs.pinentry-qt;
        programs.ssh.askPassword = lib.mkForce "${pkgs.kdePackages.ksshaskpass}/bin/ksshaskpass";

        security.polkit.enable = true;
        security.polkit.adminIdentities = lib.mkForce [ "unix-user:${user}" ];
        services.dbus.packages = [ pkgs.kdePackages.polkit-kde-agent-1 ];

        xdg.portal = {
          enable = true;
          extraPortals = lib.mkForce [
            pkgs.kdePackages.kwallet
            pkgs.kdePackages.xdg-desktop-portal-kde
            pkgs.xdg-desktop-portal-gtk
          ];
          configPackages = lib.mkForce [ pkgs.kdePackages.plasma-workspace ];
          config.common = lib.mkForce {
            default = [ "kde" ];
          };
          xdgOpenUsePortal = true;
        };

        # KDE/Qt state is intentionally persisted at normal state tier, while
        # rebuildable thumbnails, QML bytecode, icon caches, and socket/session
        # scratch files use cache tier. Source: KDE UserBase configuration file
        # hierarchy and NixOS Wiki Plasma stale-QML-cache troubleshooting.
        impermanence.home.directories = [
          ".config/KDE"
          ".config/Kvantum"
          ".config/autostart"
          ".config/dconf"
          ".config/kdedefaults"
          ".config/session"
          ".config/xsettingsd"
          ".local/share/dolphin"
          ".local/share/kactivitymanagerd"
          ".local/share/kded6"
          ".local/share/klipper"
          ".local/share/konsole"
          ".local/share/kwalletd"
          ".local/share/plasma"
          ".local/share/sddm"
        ];

        impermanence.home.files = map (file: {
          inherit file;
          method = "symlink";
        }) kdeConfigFiles;

        impermanence.home.cache.directories = [
          ".cache/plasma-svgelements"
          ".cache/plasmashell"
          ".cache/qmlcache"
          ".cache/thumbnails"
          ".local/state/wireplumber"
          "wallpaper"
        ];

        systemd.tmpfiles.rules = [
          "d ${homeDirectory}/.config 0755 ${user} users -"
          "d ${homeDirectory}/.local/share 0755 ${user} users -"
          "d ${homeDirectory}/.cache 0755 ${user} users -"
          "d ${homeDirectory}/.local/share/kwalletd 0700 ${user} users -"
          "d ${homeDirectory}/.local/share/keyrings 0700 ${user} users -"
        ]
        ++ lib.optionals config.impermanence.enable (
          # KConfig saves via temp-file rename: per-file bind mounts reject
          # that with EBUSY, while missing targets create dangling symlinks.
          # Force symlink persistence above and precreate these files here.
          # Source: nix-community/impermanence mount-file.bash symlink branch.
          [
            "d ${persistedHomeDirectory}/.config 0755 ${user} users -"
            "d ${persistedHomeDirectory}/.local/share 0755 ${user} users -"
          ]
          ++ map (file: "f ${persistedHomeDirectory}/${file} 0644 ${user} users -") kdeConfigFiles
        );
      };
    };
}
