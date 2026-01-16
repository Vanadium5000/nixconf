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

        # GUIs
        kdePackages.dolphin # File Manager
        # FIXME: plasma-systemmonitor is broken
        kdePackages.plasma-systemmonitor # System Monitor
        kdePackages.ark # Archive Manager
        kdePackages.okular # Document Viewer
        kdePackages.gwenview # Image Viewer
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
      ++ (lib.optional config.nixpkgs.config.cudaSupport pkgs.nvtopPackages.full)
      # Custom desktop packages
      ++ (with self.packages.${pkgs.stdenv.hostPlatform.system}; [
        nwg-dock-hyprland
        nwg-drawer
        rofi
        rofi-askpass
        niri-screen-time
      ]);

      services = {
        # Battery tool, required by hyprpanel
        upower.enable = true;
        # Enable CUPS printing service
        printing.enable = true;
        # GNOME virtual filesystem
        gvfs.enable = true;
        # DBus service that allows applications to query and manipulate storage devices
        udisks2.enable = true;
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

        extraPortals = # with pkgs;
          [
            # Already added by hyprland
            #xdg-desktop-portal-hyprland
          ];
      };

      # Fonts
      fonts.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        font-awesome # Icons that some apps require

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
