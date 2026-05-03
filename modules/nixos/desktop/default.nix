{ self, ... }:
{
  flake.nixosModules.desktop =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = lib.attrByPath [ "preferences" "profiles" "desktop" ] { enable = false; } config;
      # inherit (lib) getExe;
      selfpkgs = self.packages."${pkgs.stdenv.hostPlatform.system}";
    in
    {
      imports = [
        # Requirements
        self.nixosModules.terminal

        self.nixosModules.vscodium

        self.nixosModules.audio
        self.nixosModules.bluetooth

        self.nixosModules.firefox
        self.nixosModules.hyprland
        self.nixosModules.hyprland-support
        self.nixosModules.dankmemershell
        self.nixosModules.tuigreet

        self.nixosModules.obs

        self.nixosModules.qt
      ];

      config = lib.mkIf cfg.enable {
        # Start only desktop daemons not replaced by DankMaterialShell.
        preferences.autostart = [
          "niri-screen-time --daemon"
          # KDE daemon - hosts kded modules like SolidUiServer for LUKS password prompts
          "kded6"
        ];

        # DankMaterialShell replaces Waybar, the launcher, notifications,
        # lock screen, and night-light shell controls on graphical hosts.
        preferences.dankMaterialShell.enable = true;

        # Enable Localsend, a utility to share data with local devices
        programs.localsend.enable = true;

        # KDE Connect handles phone/laptop pairing on graphical hosts; the NixOS
        # module also opens the documented TCP/UDP 1714-1764 LAN range.
        # Ref: https://github.com/NixOS/nixpkgs/blob/d6ef71b2868bd85bbf92e733b03286a9f097dc7a/nixos/modules/programs/kdeconnect.nix#L29-L38
        programs.kdeconnect.enable = true;

        environment.systemPackages = [
          selfpkgs.terminal
        ]
        ++ (with pkgs; [
          # Tools
          localsend
          # The local skills.sh Playwright skill expects a `playwright-cli`
          # command, not the Playwright test runner package exposed as `playwright`.
          # Keep the binary declarative so fresh hosts do not need mutable global
          # npm installs before the skill can open a browser.
          # Ref: .agents/skills/playwright-cli/SKILL.md
          selfpkgs.playwright-cli
          selfpkgs.patchright
          # Playwright on NixOS uses nixpkgs-provided browser bundles instead of
          # upstream downloads so Chromium stays runnable under the Nix dynamic
          # linker model. Ref: https://wiki.nixos.org/wiki/Playwright
          playwright-driver.browsers

          # Video players
          vlc
          mpv

          # KDE Core Apps
          kdePackages.dolphin # File Manager
          kdePackages.ark # Archive Manager
          kdePackages.okular # Document Viewer
          kdePackages.gwenview # Image Viewer
          kdePackages.plasma-systemmonitor # System Monitor GUI

          libreoffice-qt6 # Office suite (GUI only)
          onlyoffice-desktopeditors # Office suite 2

          # KDE Frameworks & System Utilities
          kdePackages.ksystemstats # Core system statistics provider
          kdePackages.libksysguard # System monitoring library
          kdePackages.kactivitymanagerd # Runtime requirement for KDE apps
          kdePackages.kded # Required for SolidUiServer (mounting drives)
          kdePackages.plasma-workspace
          kdePackages.kwallet # Required for storing/prompting credentials
          kdePackages.kio-extras # Additional IO protocols (sftp, smb, thumbnails)
          kdePackages.kio-admin # Admin actions in Dolphin
          kdePackages.polkit-kde-agent-1 # Polkit authentication agent (Required)

          kitty # Terminal Emulator

          # CLIs
          powertop # CLI for checking battery power-draw
          wl-clipboard # System clipboard

          # XDG Integration (MIME & Desktop Entry tools)
          shared-mime-info
          desktop-file-utils

          # GTK icon themes
          # morewaita-icon-theme - Removed
          # adwaita-icon-theme - Removed
        ])
        # GPU monitoring
        ++ (lib.optional config.nixpkgs.config.cudaSupport pkgs.nvtopPackages.full);

        services = {
          # D-Bus activation for KDE services (SolidUiServer requires plasma-workspace)
          dbus.packages = [
            pkgs.kdePackages.kded
            pkgs.kdePackages.plasma-workspace
            # Expose KDE Connect's DBus activation file so kdeconnectd can start
            # on demand outside Plasma. Ref: share/dbus-1/services/org.kde.kdeconnect.service
            config.programs.kdeconnect.package
          ];

          # Battery tool, required by hyprpanel
          upower.enable = true;
          # Enable CUPS printing service
          printing.enable = true;
          # GNOME virtual filesystem
          gvfs.enable = true;
          # DBus service that allows applications to query and manipulate storage devices
          udisks2.enable = true;
          # Enable usbmuxd service for iOS devices
          usbmuxd.enable = true;
        };

        # Start the non-Plasma indicator as a user service; Hyprland does not
        # process the package's XDG autostart desktop entry itself.
        # Ref: share/applications/org.kde.kdeconnect.nonplasma.desktop
        systemd.user.services.kdeconnect-indicator = {
          description = "KDE Connect Indicator";
          wantedBy = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];

          serviceConfig = {
            ExecStart = "${config.programs.kdeconnect.package}/bin/kdeconnect-indicator";
            Restart = "on-failure";
          };
        };

        # Generic command-line automation tool (macro/autoclicker)
        programs.ydotool = {
          # Whether to enable ydotoold system service and ydotool for members of programs.ydotool.group
          enable = true;
        };

        # Graphics
        hardware = {
          graphics = {
            enable = true;
          };
        };

        # XDG Integration
        xdg.mime.enable = true;
        xdg.mime.defaultApplications = {
          # Keep LibreWolf as the human-facing default browser even though
          # Playwright gets its own Chromium bundle for automation.
          "text/html" = [ "librewolf.desktop" ];
          "application/xhtml+xml" = [ "librewolf.desktop" ];
          "x-scheme-handler/http" = [ "librewolf.desktop" ];
          "x-scheme-handler/https" = [ "librewolf.desktop" ];
          "x-scheme-handler/about" = [ "librewolf.desktop" ];
          "x-scheme-handler/unknown" = [ "librewolf.desktop" ];
        };

        # Dolphin requires applications.menu to discover apps.
        # Outside a full Plasma session, this file is missing or not detected.
        environment.etc."xdg/menus/applications.menu".source =
          "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";

        environment.sessionVariables = {
          # Tell KDE apps which menu to use
          XDG_MENU_PREFIX = "plasma-";
          # Reuse the nixpkgs Playwright browser bundle so npm/bun Playwright
          # clients do not attempt mutable browser downloads outside the store.
          # Ref: https://wiki.nixos.org/wiki/Playwright
          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          # NixOS already provides the runtime libraries, so Playwright host
          # validation should not block startup on non-FHS filesystem layouts.
          # Ref: https://wiki.nixos.org/wiki/Playwright
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
          # Keep Playwright aligned with the store-managed browser bundle above.
          PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
          # Add Flatpak exports to XDG_DATA_DIRS
          XDG_DATA_DIRS = [
            "/var/lib/flatpak/exports/share"
            "$HOME/.local/share/flatpak/exports/share"
          ];
        };

        # Rebuild KDE system configuration cache after rebuilds
        system.activationScripts.kbuildsycoca = {
          text = ''
            for dir in /home/*; do
              user="$(basename "$dir")"
              if id "$user" &>/dev/null; then
                if [ -d "$dir" ]; then
                  ${pkgs.util-linux}/bin/runuser -u "$user" -- ${pkgs.kdePackages.kservice}/bin/kbuildsycoca6 --noincremental 2>/dev/null || true
                fi
              fi
            done
          '';
          deps = [ "users" ];
        };

        # XDG Portal
        xdg.portal = {
          enable = true;
          extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
          config.common.default = "hyprland";
          xdgOpenUsePortal = true;
        };

        fonts.packages = with pkgs; [
          nerd-fonts.jetbrains-mono
          font-awesome
          roboto
          work-sans
          comic-neue
          source-sans
          comfortaa
          inter
          lato
          lexend
          jost
          dejavu_fonts
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          openmoji-color
          twemoji-color-font
          self.packages.${pkgs.stdenv.hostPlatform.system}.aptos-fonts
        ];

        # Safeeyes - A uitlity to remind the user to look away from the screen every x minutes
        # NOTE: Quite annoying tho
        # services.safeeyes.enable = true;
      };
    };
}
