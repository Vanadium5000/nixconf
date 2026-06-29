{ self, inputs, ... }:
{
  flake.nixosConfigurations.macbook = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.macbookHost
    ];
  };

  flake.nixosModules.macbookHost =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      imports = [
        self.nixosModules.desktop
        self.nixosModules.cockpit

        # Drivers and settings, https://github.com/NixOS/nixos-hardware/blob/master/flake.nix
        inputs.nixos-hardware.nixosModules.common-cpu-intel
        inputs.nixos-hardware.nixosModules.apple-t2
        inputs.nixos-hardware.nixosModules.common-hidpi
        inputs.nixos-hardware.nixosModules.common-pc-ssd

        # TLP (increased battery-life on laptops)
        self.nixosModules.tlp

        # Disko
        inputs.disko.nixosModules.disko
        self.diskoConfigurations.macbook
      ];

      # Enable SSH support
      users.users.${config.preferences.user.username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsIUmSPfK9/ncfGjINjeI7sz+QK7wyaYJZtLhVpiU66 ssh-admin@macbook"

        # NOTE: iPad Termius Key
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEg7swCzJy8e8D+gQUtGW6YEdTt6j8RMRBR89Nhco9c+"
      ];

      # T2 latest currently tracks the removed linux_6_19 attr; stable tracks the
      # supported linux_6_12 T2 patchset in nixos-hardware.
      # Source: https://github.com/NixOS/nixos-hardware/blob/master/apple/t2/pkgs/linux-t2/default.nix
      hardware.apple-t2.kernelChannel = "stable";

      # Preferences
      preferences = {
        hostName = "macbook";
        profiles = {
          terminal.enable = true;
          desktop.enable = true;
          laptop.enable = true;
        };
        user = {
          username = "matrix";
        };
        hardware.tlp.enable = true;
        hardware.memory.enable = true;
        hardware.btrfsMaintenance.enable = true;
        system = {
          backlightDevice = "acpi_video0";
          keyboardBacklightDevice = "apple::kbd_backlight";
        };
        obsidian.enable = true;
      };

      # Plymouth
      # boot.plymouth.enable = true;

      # (cdc_ncm, cdc_mbim) prevent networkmanager spam from unusable cdc devices
      # (hci_bcm4377) disable bluetooth as it's very buggy on a MacBookAir9,1
      # boot.blacklistedKernelModules = [
      #   "cdc_ncm"
      #   "cdc_mbim"
      #   "hci_bcm4377"
      # ];
      # Keyboard
      services.xserver.xkb.layout = "gb";
      services.xserver.xkb.variant = ""; # mac
      console.useXkbConfig = true;

      # Enabled by most DEs & by steam anyways
      hardware.graphics.enable = true;

      # Make audio sound better
      # services.pipewire = {
      #   extraConfig = {
      #     pipewire-pulse."92-fix-crackle" = {
      #       "pulse.properties" = {
      #         "pulse.properties" = {
      #           "pulse.min.req" = "1024/48000";
      #           "pulse.default.req" = "1024/48000";
      #           "pulse.max.req" = "1024/48000";
      #           "pulse.min.quantum" = "1024/48000";
      #           "pulse.max.quantum" = "1024/48000";
      #         };
      #         "stream.properties" = {
      #           "node.latency" = "1024/48000";
      #           "resample.quality" = 1;
      #         };
      #       };
      #     };
      #     pipewire."92-fix-crackle" = {
      #       "context.properties" = {
      #         "default.clock.rate" = 48000;
      #         "default.clock.quantum" = 1024;
      #         "default.clock.min-quantum" = 1024;
      #         "default.clock.max-quantum" = 1024;
      #       };
      #     };
      #   };
      # };

      # Switch cmd with option, and fn with ctrl: for a more normal keyboard layout
      # home-manager.users.${config.var.username} = {
      #   wayland.windowManager.hyprland.settings.input.kb_options = "super:swapalt,function:swapctrl";
      # };

      # Swap fn & ctrl, opt & cmd
      boot.extraModprobeConfig = ''
        options hid_apple fnmode=1 swap_fn_leftctrl=1 swap_opt_cmd=1
      '';

      # Macbook T2 wifi firmware https://wiki.t2linux.org/distributions/nixos/installation/#__tabbed_7_2
      hardware.firmware = [
        (pkgs.stdenvNoCC.mkDerivation (final: {
          name = "brcm-firmware";
          src = ./_firmware.tar;

          dontUnpack = true;
          installPhase = ''
            mkdir -p $out/lib/firmware/brcm
            tar -xf ${final.src} -C $out/lib/firmware/brcm
          '';
        }))
      ];

      # HTTPS traffic analyzer — on-demand: systemctl start mitmproxy
      services.mitmproxy.enable = true;
      services.mitmproxy.trustCA = true;
      services.cockpit-managed = {
        enable = true;
        host = "0.0.0.0";
        port = 9090;
        openFirewall = false;
      };
      services.ntfy-sh = {
        enable = true;
        settings = {
          # Bind on all interfaces so the service is reachable over Tailscale.
          # The normal firewall stays closed; tailscale0 is already trusted separately.
          listen-http = "0.0.0.0:2586";

          # Required by ntfy for attachment download links on self-hosted instances.
          # Tailscale DNS keeps the URL stable across IP changes.
          base-url = "http://macbook:2586";
          upstream-base-url = "https://ntfy.sh";

          # Keep attachments simple and enabled without introducing auth or extra proxying.
          attachment-cache-dir = "/var/lib/ntfy-sh/attachments";
        };
      };
      systemd.services.ntfy-sh.serviceConfig.DynamicUser = lib.mkForce false;
      services.vpn-proxy.enable = true;
      services.unison-sync.enable = true;
      services.hypridle.enable = true;

      # ntfy keeps its cache, auth DB, and attachments in /var/lib/ntfy-sh.
      # Use a normal persistent state path to avoid DynamicUser StateDirectory clashes.
      impermanence.nixos.directories = [ "/var/lib/ntfy-sh" ];

      # No cuda - doesn't have an Nvidia GPU
      nixpkgs.config.cudaSupport = false;

      # State version
      system.stateVersion = "25.11";
    };
}
