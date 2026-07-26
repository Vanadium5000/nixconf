{ self, ... }:
let
  inherit (self) secrets;
in
{
  flake.nixosModules.main_vpsHost =
    { lib, pkgs, ... }:
    let
      initrdUnlockPort = 22;
      initrdUnlockShell = pkgs.writeTextFile {
        name = "main-vps-initrd-unlock-shell";
        destination = "/bin/main-vps-initrd-unlock-shell";
        executable = true;
        text = ''
          #!/bin/sh
          exec /bin/systemctl default
        '';
      };
      initrdUnlockHostKey = pkgs.writeText "main-vps-initrd-ssh-host-ed25519-key" (
        secrets.MAIN_VPS_INITRD_SSH_HOST_KEY
      );
      initrdUnlockAuthorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsIUmSPfK9/ncfGjINjeI7sz+QK7wyaYJZtLhVpiU66 ssh-admin@main-vps"
      ];
    in
    {
      boot.initrd.network = {
        # Remote unlock runs before NetworkManager and normal OpenSSH exist, so
        # stage-1 networking must be enabled explicitly. With systemd stage 1,
        # DHCP is handled by boot.initrd.systemd.network rather than udhcpc.
        # Source: https://wiki.nixos.org/wiki/Remote_disk_unlocking
        enable = true;

        ssh = {
          # Open an initrd-only SSH daemon for LUKS unlock; normal post-boot SSH is
          # still configured separately in modules/common/base.nix. Source:
          # https://github.com/NixOS/nixpkgs/blob/4f90e32d9c535072f0a6a9ac4599f1e78b829eab/nixos/modules/system/boot/initrd-ssh.nix#L99-L120
          enable = true;

          # Use the normal SSH port in initrd because provider firewalls commonly
          # allow :22 while blocking high ports; stage-2 sshd starts only after
          # unlock, so there is no listener collision.
          # Source: https://wiki.nixos.org/wiki/Remote_disk_unlocking#Usage
          port = initrdUnlockPort;

          # The initrd SSH server host key is loaded from password-store through
          # rebuild.sh -> secrets.nix -> self.secrets, so switching does not depend
          # on any mutable /etc/ssh or /persist key file existing on the VPS.
          # Source:
          # https://github.com/NixOS/nixpkgs/blob/4f90e32d9c535072f0a6a9ac4599f1e78b829eab/nixos/modules/system/boot/initrd-ssh.nix#L57-L87
          hostKeys = [ initrdUnlockHostKey ];

          # Reuse the existing admin public key for unlock auth only; this does not
          # grant a post-boot login beyond the separate OpenSSH configuration.
          authorizedKeys = initrdUnlockAuthorizedKeys;
        };
      };

      boot.initrd.systemd = {
        shell.enable = true;
        storePaths = [ "${initrdUnlockShell}/bin/main-vps-initrd-unlock-shell" ];
        users.root.shell = "${initrdUnlockShell}/bin/main-vps-initrd-unlock-shell";

        network = {
          enable = true;
          wait-online.anyInterface = true;
          networks."10-initrd-ethernet" = {
            matchConfig.Name = "ens* en* eth*";
            networkConfig.DHCP = "ipv4";
          };
        };
      };
    };
}
