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
        self.nixosModules.desktop

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

      # Enable SSH support
      users.users.${config.preferences.user.username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsIUmSPfK9/ncfGjINjeI7sz+QK7wyaYJZtLhVpiU66 thealfiecrawford@icloud.com"
      ];

      # Use the latest kernel
      boot.kernelPackages = pkgs.linuxPackages_latest; # 6.14+ for rtw89_8852bu USB support

      # Preferences
      preferences = {
        hostName = "legion5i";
        profiles = {
          terminal.enable = true;
          desktop.enable = true;
          laptop.enable = true;
        };
        user = {
          username = "matrix";
        };
        hardware.tlp.enable = true;
        system = {
          backlightDevice = "intel_backlight";
          keyboardBacklightDevice = "platform::kbd_backlight";
        };
        git = {
          username = "Vanadium5000";
          email = "vanadium5000@gmail.com";
        };
        obs.enable = true;
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

        # The open kernel module currently fails to build against this linuxPackages_latest snapshot
        # because Linux 6.19 made vm_flags writes go through accessors. Stay on the proprietary
        # module until the selected nixpkgs driver branch carries the upstream compatibility fix.
        open = false;

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

      # HTTPS traffic analyzer — on-demand: systemctl start mitmproxy
      services.mitmproxy.enable = true;
      services.mitmproxy.trustCA = true;
      services.ntfy-sh = {
        enable = true;
        settings = {
          # Bind on all interfaces so the service is reachable over Tailscale.
          # The normal firewall stays closed; tailscale0 is already trusted separately.
          listen-http = "0.0.0.0:2586";

          # Required by ntfy for attachment download links on self-hosted instances.
          # Tailscale DNS keeps the URL stable across IP changes.
          base-url = "http://legion5i:2586";

          # Keep attachments simple and enabled without introducing auth or extra proxying.
          attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
        };
      };
      services.vpn-proxy.enable = true;
      services.unison-sync.enable = true;
      services.hyprsunset.enable = true;
      services.hypridle.enable = true;
      programs.hyprlock.enable = true;

      # ntfy-sh runs with DynamicUser + StateDirectory, so systemd manages the real
      # state under /var/lib/private/ntfy-sh and bind-mounts it into the service.
      # Persist the private backing directory to avoid clashing with systemd's setup.
      impermanence.nixos.directories = [ "/var/lib/private/ntfy-sh" ];

      # State version
      system.stateVersion = "25.11";
    };
}
