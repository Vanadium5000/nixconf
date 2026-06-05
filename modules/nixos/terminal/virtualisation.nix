{ self, ... }:
{
  flake.nixosModules.virtualisation =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
      cfg = config.preferences.waydroid;
      waydroidPackage = pkgs.waydroid-nftables;
      waydroidManagedProperties =
        cfg.extraProperties
        // lib.optionalAttrs cfg.softwareRendering {
          # Source: https://docs.waydro.id/faq/get-waydroid-to-work-through-a-vm
          # The GBM/Mesa path is crashing Android SurfaceFlinger on this hybrid Intel/NVIDIA host; SwiftShader trades speed for a stable compositor.
          "ro.hardware.gralloc" = "default";
          "ro.hardware.egl" = "swiftshader";
          "ro.hardware.vulkan" = "";
          "persist.waydroid.no_presentation" = "true";
        };
      waydroidManagedPropertiesJson = builtins.toJSON waydroidManagedProperties;
      waydroidApplyConfigPython = pkgs.writeText "waydroid-apply-config.py" ''
        import configparser
        import json
        import os
        import sys
        from pathlib import Path

        cfg_path = Path(sys.argv[1])
        base_prop = Path(sys.argv[2])
        managed = json.loads(os.environ["WAYDROID_MANAGED_PROPERTIES"])

        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.optionxform = str
        parser.read(cfg_path)

        if not parser.has_section("properties"):
            parser.add_section("properties")

        changed = False
        for key, value in managed.items():
            current = parser["properties"].get(key)
            if current != value:
                parser["properties"][key] = value
                changed = True

        if changed:
            tmp_path = cfg_path.with_suffix(cfg_path.suffix + ".tmp")
            with tmp_path.open("w") as handle:
                parser.write(handle)
            tmp_path.replace(cfg_path)
            print("changed")
            raise SystemExit

        if base_prop.exists():
            current_props = {}
            for line in base_prop.read_text(errors="replace").splitlines():
                if not line or line[0] in "#;" or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                current_props[key.strip()] = value.strip()
            for key, value in managed.items():
                if current_props.get(key) != value:
                    print("base-stale")
                    raise SystemExit

        print("ok")
      '';
      waydroidApplyConfig = pkgs.writeShellScriptBin "waydroid-apply-config" ''
        set -euo pipefail

        cfg_path=/var/lib/waydroid/waydroid.cfg
        base_prop=/var/lib/waydroid/waydroid_base.prop

        if [[ ! -f "$cfg_path" ]]; then
          exit 0
        fi

        state="$(${pkgs.python3}/bin/python3 ${waydroidApplyConfigPython} "$cfg_path" "$base_prop")"
        case "$state" in
          changed|base-stale)
            ${waydroidPackage}/bin/waydroid upgrade --offline
            ;;
        esac
      '';
    in
    {
      options.preferences.waydroid = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = config.preferences.profiles.desktop.enable;
          description = "Enable the Waydroid Android container on graphical hosts.";
        };

        softwareRendering = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Force Waydroid through SwiftShader instead of the host GBM/Mesa compositor path.";
        };

        extraProperties = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Additional Android properties maintained in /var/lib/waydroid/waydroid.cfg.";
        };
      };

      programs.virt-manager.enable = true;

      virtualisation = {
        docker = {
          enable = true;
          daemon.settings.live-restore = false;
        };
        podman = {
          enable = false;
          dockerCompat = false;
        };

        libvirtd.enable = true;
        oci-containers.backend = "docker";
      };

      # Use nvidia with Docker - https://discourse.nixos.org/t/nvidia-docker-container-runtime-doesnt-detect-my-gpu/51336
      hardware.nvidia-container-toolkit.enable = config.nixpkgs.config.cudaSupport;

      environment.systemPackages =
        with pkgs;
        [
          dive # look into docker image layers
          docker-compose # start group of containers for dev

          qemu # virtualisation

          selfpkgs.waydroid-script # Keep this local so update-pkgs can track the exact commit pinned by this flake.
        ]
        ++ lib.optionals cfg.enable [ waydroidApplyConfig ];

      virtualisation.waydroid = lib.mkIf cfg.enable {
        enable = true;
        package = waydroidPackage;
      };

      systemd.services.waydroid-container = lib.mkIf cfg.enable {
        serviceConfig.Environment = "WAYDROID_MANAGED_PROPERTIES=${waydroidManagedPropertiesJson}";
        preStart = ''
          ${waydroidApplyConfig}/bin/waydroid-apply-config
        '';
      };

      # Persist Waydroid's Android /data as system state: Android numeric UIDs
      # must survive untouched, while user persistence can chown entries to the
      # host user and break core services such as keystore2; desktop entries are
      # user-owned launchers regenerated from Android apps, so keep them in home.
      impermanence.home.cache.directories = [
        ".local/share/applications"
        ".cache/waydroid-script"

        # VM Data
        ".config/libvirt"
      ];
      impermanence.nixos.cache.directories = [
        "/var/lib/waydroid"
        {
          directory = "/home/${config.preferences.user.username}/.local/share/waydroid";
          user = "root";
          group = "root";
          mode = "0755";
        }

        # Docker & other VM Data
        "/var/lib/docker"
        "/var/lib/libvirt"
        "/etc/libvirt/qemu"
      ];
    };
}
