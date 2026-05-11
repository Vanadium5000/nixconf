{ self, ... }:
let
  inherit (self) secrets;
in
{
  flake.nixosModules.main_vpsHost =
    { lib, pkgs, ... }:
    let
      initrdUnlockPort = 2222;
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
        # stage-1 networking must be enabled explicitly. Source:
        # https://github.com/NixOS/nixpkgs/blob/4f90e32d9c535072f0a6a9ac4599f1e78b829eab/nixos/modules/system/boot/initrd-network.nix#L58-L70
        enable = true;

        udhcpc = {
          # The live IONOS VPS uses DHCP on ens6, including a /32 IPv4 address and
          # provider gateway; initrd cannot inherit that from normal boot.
          # Assumption: provider DHCP is also available in initrd; if not, replace
          # this with an explicit ip= kernel parameter after console testing.
          enable = true;
        };

        ssh = {
          # Open an initrd-only SSH daemon for LUKS unlock; normal post-boot SSH is
          # still configured separately in modules/common/base.nix. Source:
          # https://github.com/NixOS/nixpkgs/blob/4f90e32d9c535072f0a6a9ac4599f1e78b829eab/nixos/modules/system/boot/initrd-ssh.nix#L99-L120
          enable = true;

          # Keep stage-1 SSH away from the normal port 22 service, making it clear
          # that a connection here is for unlocking the booted generation only.
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

        # Drop directly into the NixOS LUKS passphrase helper after SSH login so a
        # headless reboot needs only `ssh -p 2222 root@<host>`. Source:
        # https://wiki.nixos.org/wiki/Remote_LUKS_Unlocking
        postCommands = lib.mkAfter ''
          echo 'cryptsetup-askpass' >> /root/.profile
        '';
      };
    };
}
