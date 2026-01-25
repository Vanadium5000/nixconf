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
        self.nixosModules.hyprsunset
        self.nixosModules.tuigreet

        self.nixosModules.extra_hjem

        self.nixosModules.qt
      ];

      # Wireshark - QT Version for Desktop
      programs.wireshark.package = lib.mkForce pkgs.wireshark;

      # Automatically start waybar & swaync & niri-screen-time daemon
      preferences.autostart = [
        "waybar"
        "swaync"
        "niri-screen-time --daemon"
        # KDE daemon - hosts kded modules like SolidUiServer for LUKS password prompts
        "kded6"
      ];

      # Enable Localsend, a utility to share data with local devices
      programs.localsend.enable = true;

      environment.systemPackages = [
        selfpkgs.terminal
        selfpkgs.waybar
      ]
      ++ (with pkgs; [
        # Utils
        swaynotificationcenter

        # Tools
        localsend

        # Video players
        vlc
        mpv

        # KDE Core Apps
        kdePackages.dolphin # File Manager
        kdePackages.ark # Archive Manager
        kdePackages.okular # Document Viewer
        kdePackages.gwenview # Image Viewer
        kdePackages.plasma-systemmonitor # System Monitor GUI

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

        # BTRFS
        btdu # Disk usage

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

      # XDG Portal
      xdg.portal = {
        enable = true;
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
      ];

      # Safeeyes - A uitlity to remind the user to look away from the screen every x minutes
      # NOTE: Quite annoying tho
      # services.safeeyes.enable = true;
    };
}
