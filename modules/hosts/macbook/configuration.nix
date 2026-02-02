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
      config,
      ...
    }:
    {
      imports = [
        self.nixosModules.desktop

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
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsIUmSPfK9/ncfGjINjeI7sz+QK7wyaYJZtLhVpiU66 thealfiecrawford@icloud.com"

        # NOTE: iPad Termius Key
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDZ4tcgk5qphCpwoaDUCl1ixCNUSpIrVMz8XB0OHcOz2"
      ];

      # Use the latest kernel
      hardware.apple-t2.kernelChannel = "latest"; # 6.14+ for rtw89_8852bu USB support

      # Open firewall for Local Web Development
      networking.firewall.allowedTCPPorts = [
        5173 # Vite - Frontend
        3000 # Backend
        4096 # OpenCode
      ];

      # Preferences
      preferences = {
        hostName = "macbook";
        user = {
          username = "matrix";
        };
        system = {
          backlightDevice = "acpi_video0";
          keyboardBacklightDevice = "apple::kbd_backlight";
        };
        git = {
          username = "Vanadium5000";
          email = "vanadium5000@gmail.com";
        };
      };

      # Plymouth
      boot.plymouth.enable = true;

      # (cdc_ncm, cdc_mbim) prevent networkmanager spam from unusable cdc devices
      # (hci_bcm4377) disable bluetooth as it's very buggy on a MacBookAir9,1
      boot.blacklistedKernelModules = [
        "cdc_ncm"
        "cdc_mbim"
        "hci_bcm4377"
      ];
      # Workaround for suspend/resume issues on T2 Macs
      systemd.services."suspend-fix-t2" = {
        enable = true;
        unitConfig = {
          Description = "Disable and Re-Enable Apple BCE Module (and Wi-Fi)";
          Before = "sleep.target";
          StopWhenUnneeded = "yes";
        };
        serviceConfig = {
          User = "root";
          Type = "oneshot";
          RemainAfterExit = "yes";
          ExecStart = [
            "/run/current-system/sw/bin/modprobe -r brcmfmac_wcc"
            "/run/current-system/sw/bin/modprobe -r brcmfmac"
            "/run/current-system/sw/bin/rmmod -f apple-bce"
          ];
          ExecStop = [
            "/run/current-system/sw/bin/modprobe apple-bce"
            "/run/current-system/sw/bin/modprobe brcmfmac"
            "/run/current-system/sw/bin/modprobe brcmfmac_wcc"
          ];
        };
        wantedBy = [ "sleep.target" ];
      };

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

      # Brightness keys
      # home-manager.users."${config.var.username}".wayland.windowManager.hyprland.settings.bindle = [
      #   ",XF86KbdBrightnessUp, exec, brightness-up 'apple::kbd_backlight'" # Kbd Brightness Up
      #   ",XF86KbdBrightnessDown, exec, brightness-down 'apple::kbd_backlight'" # Kbd Brightness Down
      #   "$shift,XF86KbdBrightnessUp, exec, brightness-up-small 'apple::kbd_backlight'" # Kbd Brightness Up Small
      #   "$shift,XF86KbdBrightnessDown, exec, brightness-down-small 'apple::kbd_backlight'" # Kbd Brightness Down Small
      # ];

      # No cuda - doesn't have an Nvidia GPU
      nixpkgs.config.cudaSupport = false;

      # State version
      system.stateVersion = "25.11";
    };
}
