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
      ++ (lib.optional config.nixpkgs.config.cudaSupport [ pkgs.nvtopPackages.full ]);

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
    };
}
