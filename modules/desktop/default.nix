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
      opensnitchRule = name: description: operator: {
        inherit name description operator;
        created = "2026-07-09T00:00:00Z";
        updated = "2026-07-09T00:00:00Z";
        action = "allow";
        duration = "always";
        enabled = true;
        precedence = true;
        nolog = false;
      };
      simple = operand: data: {
        type = "simple";
        inherit operand data;
        sensitive = false;
        list = null;
      };
      list = operators: {
        type = "list";
        operand = "list";
        data = "";
        sensitive = false;
        list = operators;
      };
    in
    {
      imports = [
        # Requirements
        self.nixosModules.terminal

        self.nixosModules.vscodium

        self.nixosModules.audio
        self.nixosModules.bluetooth
        self.nixosModules.hdmi-cec

        self.nixosModules.firefox
        self.nixosModules.kde

        self.nixosModules.obs
        self.nixosModules.obsidian
      ];

      config = lib.mkIf cfg.enable {
        # Enable Localsend, a utility to share data with local devices
        programs.localsend.enable = true;

        services.opensnitch.mutableRules = lib.mkIf config.services.opensnitch.enable {
          "030-allow-librewolf-browser" =
            opensnitchRule "030-allow-librewolf-browser" "Allow the system LibreWolf browser binary."
              {
                type = "simple";
                operand = "process.path";
                data = "${lib.getExe pkgs.librewolf}";
                sensitive = false;
                list = null;
              };
          "060-allow-lyricsctl-providers" =
            opensnitchRule "060-allow-lyricsctl-providers"
              "Allow the packaged lyricsctl wrapper to query LRCLIB and lrc.cx only; do not allow Bun globally."
              (list [
                {
                  type = "regexp";
                  operand = "process.command";
                  data = "^${selfpkgs.lyricsctl}/bin/lyricsctl .*synced-lyrics\\.ts.*";
                  sensitive = false;
                  list = null;
                }
                {
                  type = "regexp";
                  operand = "dest.host";
                  data = "^(lrclib\\.net|api\\.lrc\\.cx)$";
                  sensitive = false;
                  list = null;
                }
                (simple "dest.port" "443")
              ]);
        };

        # KDE Connect handles phone/laptop pairing on graphical hosts; the NixOS
        # module also opens the documented TCP/UDP 1714-1764 LAN range.
        # Ref: https://github.com/NixOS/nixpkgs/blob/d6ef71b2868bd85bbf92e733b03286a9f097dc7a/nixos/modules/programs/kdeconnect.nix#L29-L38
        programs.kdeconnect.enable = true;

        environment.systemPackages = [
          selfpkgs.terminal
          pkgs.unstable.ghostty
        ]
        ++ (with pkgs; [
          # Tools
          localsend
          selfpkgs.lyricsctl

          # Video players
          vlc
          mpv

          # Tools
          unstable.scanmem

          # KDE Core Apps
          kdePackages.dolphin # File Manager
          kdePackages.ark # Archive Manager
          kdePackages.okular # Document Viewer
          kdePackages.gwenview # Image Viewer

          # KDE / Qt System Administration
          kdePackages.plasma-systemmonitor # System Monitor GUI
          kdePackages.partitionmanager

          libreoffice-qt6 # Office suite (GUI only)
          onlyoffice-desktopeditors # Office suite 2

          # KDE Frameworks & System Utilities
          # Plasma System Monitor sensor faces import QuickCharts, and Kirigami
          # needs Plasma/QQC2 style plugins outside a full Plasma session.
          # Ref: nixos/modules/services/desktop-managers/plasma6.nix.
          kdePackages.kquickcharts
          kdePackages.libplasma
          kdePackages.qqc2-breeze-style
          kdePackages.qqc2-desktop-style
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
          glib # Provides `gio trash`; Electron/VSCodium needs it on PATH for Trash deletes.

          # QtMultimedia dlopens libpipewire-0.3 for KMail's message viewer;
          # putting PipeWire in the profile makes the library discoverable even
          # when the app is not launched from a full Plasma environment.
          # Ref: qt/multimedia/src/plugins/multimedia/ffmpeg/qffmpegsymbolsresolveutils.cpp.
          pipewire

          # GTK icon themes
          # morewaita-icon-theme - Removed
          # adwaita-icon-theme - Removed
        ])
        # GPU monitoring
        ++ (lib.optional config.nixpkgs.config.cudaSupport pkgs.nvtopPackages.full);

        # KMail needs the full KDE PIM base on the system profile so Akonadi
        # agents, resources, and the account wizard are discoverable outside Plasma.
        # Ref: nixos/modules/programs/kde-pim.nix; NixOS/nixpkgs#292450.
        programs.kde-pim = {
          enable = true;
          kmail = true;
        };

        # Akonadi resource/agent definitions live under share/akonadi/agents.
        # Link that tree into /run/current-system/sw so DBus-activated Akonadi
        # can resolve default resources such as akonadi_maildir_resource; without
        # it KMail aborts on startup with "Unable to obtain agent type ''.".
        # Ref: akonadi src/core/jobs/agentinstancecreatejob.cpp.
        environment.pathsToLink = [ "/share/akonadi" ];

        services = {
          # D-Bus activation for KDE services (SolidUiServer requires plasma-workspace)
          dbus.packages = [
            pkgs.kdePackages.kded
            pkgs.kdePackages.plasma-workspace
            # Plasma System Monitor queries org.kde.ksystemstats1 over DBus;
            # ksystemstats ships the activator, libksysguard ships the DBus
            # interface/helper bits. Ref: ksystemstats share/dbus-1/services.
            pkgs.kdePackages.ksystemstats
            pkgs.kdePackages.libksysguard
            # Expose KDE Connect's DBus activation file so kdeconnectd can start
            # on demand outside Plasma. Ref: share/dbus-1/services/org.kde.kdeconnect.service
            config.programs.kdeconnect.package
          ];

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

        # Graphics
        hardware = {
          graphics = {
            enable = true;
          };
        };

        # KMail/Akonadi account/resource config and local mail/contact data are
        # user state; browser/IDE caches are declared beside those applications.
        # Sources: KDE UserBase KMail migration + Akonadi storage docs.
        impermanence.home.directories = [
          ".config/akonadi"
          ".local/share/akonadi"
          ".local/share/contacts"
          ".local/share/emailidentities"
          ".local/share/kmail2"
          ".local/share/local-mail"
        ];
        impermanence.home.files = [
          ".config/emaildefaults"
          ".config/emailidentities"
          ".config/kmail2rc"
        ];
        impermanence.home.cache.directories = [ ];
        # XDG Integration
        # Enable the NixOS XDG generators so non-Plasma sessions still expose
        # desktop files, icons, autostart entries, and terminal handlers.
        # Ref: nixos/options xdg.{autostart,icons,menus,terminal-exec}.enable
        xdg.autostart.enable = true;
        xdg.icons.enable = true;
        xdg.menus.enable = true;
        xdg.terminal-exec.enable = true;
        xdg.mime.enable = true;
        xdg.mime.defaultApplications = {
          # Desktop id from pkgs.librewolf share/applications/librewolf.desktop.
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
          # Default CLI/xdg browser; matches xdg.mime handlers above.
          BROWSER = "librewolf";
          # Tell KDE apps which menu to use
          XDG_MENU_PREFIX = "plasma-";
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
          # Prefer the KDE portal for file pickers so apps get a Qt/Dolphin-style
          # chooser; GTK covers generic portal APIs outside a full Plasma session.
          config.common = {
            default = [ "gtk" ];
            "org.freedesktop.impl.portal.FileChooser" = "kde";
          };
          xdgOpenUsePortal = true;
        };

        fonts.packages = with pkgs; [
          nerd-fonts.jetbrains-mono
          nerd-fonts.symbols-only
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
        ];

        # Safeeyes - A uitlity to remind the user to look away from the screen every x minutes
        # NOTE: Quite annoying tho
        # services.safeeyes.enable = true;
      };
    };
}
