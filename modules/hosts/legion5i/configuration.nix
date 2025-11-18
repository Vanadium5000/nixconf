{ self, inputs, ... }:
{
  flake.nixosConfigurations.legion5i = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.legion5iHost
    ];
  };

  flake.nixosModules.legion5iHost =
    {
      pkgs,
      config,
      ...
    }:
    {
      imports = [
        self.nixosModules.terminal

        # Drivers and settings, https://github.com/NixOS/nixos-hardware/blob/master/flake.nix
        inputs.nixos-hardware.nixosModules.common-cpu-intel
        inputs.nixos-hardware.nixosModules.common-gpu-nvidia
        inputs.nixos-hardware.nixosModules.common-hidpi
        inputs.nixos-hardware.nixosModules.common-pc-ssd

        # TLP (increased battery-life on laptops)
        self.nixosModules.tlp

        # Disko
        inputs.disko.nixosModules.disko
        self.diskoConfigurations.legion5i
      ];

      # Declare the HOST as an environment variable for use in scripts, etc.
      environment.variables.HOST = "legion5i";

      # Enable SSH support
      users.users.${config.preferences.user.username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsIUmSPfK9/ncfGjINjeI7sz+QK7wyaYJZtLhVpiU66 thealfiecrawford@icloud.com"
      ];

      # Preferences
      preferences = {
        user = {
          username = "matrix";
        };
        system = {
          backlightDevice = "intel_backlight";
          keyboardBacklightDevice = "platform::kbd_backlight";
        };
      };

      # Plymouth
      boot.plymouth.enable = true;

      # Keyboard
      services.xserver.xkb.layout = "gb";
      services.xserver.xkb.variant = ""; # mac
      console.useXkbConfig = true;

      # Enabled by most DEs & by steam anyways
      hardware.graphics.enable = true;

      hardware.nvidia = {
        # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
        # Enable this if you have graphical corruption issues or application crashes after waking
        # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
        # of just the bare essentials.
        powerManagement.enable = true;

        # Fine-grained power management. Turns off GPU when not in use.
        # Experimental and only works on modern Nvidia GPUs (Turing or newer).
        powerManagement.finegrained = true;

        # It is suggested to use the open source kernel modules on Turing or later GPUs (RTX series, GTX 16xx)
        open = true;

        prime = {
          # Make sure to use the correct Bus ID values for your system!
          # You can find them using "sudo lshw -c display"
          intelBusId = "PCI:0:2:0"; # integrated
          nvidiaBusId = "PCI:1:0:0"; # dedicated
        };

        # Select the appropriate driver version for the GPU
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };

      # Enable cuda support in programs despite it being unfree
      nixpkgs.config.cudaSupport = true;

      # Add these environment variables for better CUDA support
      environment.variables = {
        # Your existing variables ...
        CUDA_PATH = "${pkgs.cudatoolkit}";
        LD_LIBRARY_PATH =
          "${pkgs.cudatoolkit}/lib:${pkgs.cudaPackages.cudnn}/lib"
          # https://github.com/anotherhadi/nixy/blob/main/home/programs/shell/zsh.nix
          + ":${config.hardware.nvidia.package}/lib:$LD_LIBRARY_PATH"; # Extra for btop nvidia support
      };

      # State version
      system.stateVersion = "25.11";
    };
}
