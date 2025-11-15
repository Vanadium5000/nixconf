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

        self.nixosModules.chromium
        self.nixosModules.firefox
        self.nixosModules.hyprland
        self.nixosModules.hyprsunset
        self.nixosModules.tuigreet

        self.nixosModules.extra_hjem
      ];

      # Automatically start waybar & swaync
      preferences.autostart = [
        "waybar"
        "swaync"
      ];

      environment.systemPackages = [
        selfpkgs.terminal
        selfpkgs.waybar
      ]
      ++ (with pkgs; [
        # Utils
        swaynotificationcenter

        # GUIs
        nautilus # File Manager
        kitty # Terminal Emulator

        # CLIs
        powertop # CLI for checking battery power-draw
        wl-clipboard # System clipboard

        # BTRFS
        btdu # Disk usage

        # GTK icon themes
        morewaita-icon-theme
        adwaita-icon-theme
      ])
      # GPU monitoring
      ++ (lib.optional config.nixpkgs.config.cudaSupport [ pkgs.nvtopPackages.full ])
      # Custom desktop packages
      ++ (with self.packages.${pkgs.stdenv.hostPlatform.system}; [
        nwg-dock-hyprland
        nwg-drawer
        rofi
        rofi-askpass
      ]);

      fonts.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
      ];

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
        config.common.default = "gtk";
        xdgOpenUsePortal = true;

        extraPortals = with pkgs; [
          # Already added by hyprland
          #xdg-desktop-portal-hyprland

          # GTK
          xdg-desktop-portal-gtk
        ];
      };

      # Safeeyes - A uitlity to remind the user to look away from the screen every x minutes
      services.safeeyes.enable = true;
    };
}
