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
        self.nixosModules.dankmaterialshell
        self.nixosModules.firefox
        self.nixosModules.hyprland
        self.nixosModules.tuigreet

        self.nixosModules.extra_hjem
      ];

      environment.systemPackages = [
        selfpkgs.terminal
      ]
      ++ (with pkgs; [
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

      # Environment Variables
      environment.variables = {
        XDG_SESSION_TYPE = "wayland";
        XDG_SESSION_DESKTOP = "Hyprland";
        XDG_CURRENT_DESKTOP = "Hyprland";
        MOZ_ENABLE_WAYLAND = "1";
        ANKI_WAYLAND = "1";

        NIXOS_OZONE_WL = "1";
        DISABLE_QT5_COMPAT = "0";
        GDK_BACKEND = "wayland";
        DIRENV_LOG_FORMAT = "";
        WLR_DRM_NO_ATOMIC = "1";

        #QT_QPA_PLATFORMTHEME = lib.mkForce "kde";

        QT_AUTO_SCREEN_SCALE_FACTOR = "1"; # enables automatic scaling
        QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
        QT_QPA_PLATFORM = "wayland";

        WLR_BACKEND = "vulkan";
        WLR_RENDERER = "vulkan";
        WLR_NO_HARDWARE_CURSORS = "1";

        #SDL_VIDEODRIVER = "wayland";
        CLUTTER_BACKEND = "wayland";

        GSK_RENDERER = "vulkan"; # "ngl" | "vulkan"

        FLAKE = config.preferences.configDirectory; # Config Directory
      };

      # Graphics
      hardware = {
        graphics = {
          enable = true;
        };
      };
    };
}
