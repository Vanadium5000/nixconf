{
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    {
      packages.rofi-passmenu = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "rofi-passmenu" ''
          exec ${pkgs.bun}/bin/bun run ${./passmenu.ts} "$@"
        '';
        env = {
          # Ensure PATH includes all runtime inputs
          PATH = pkgs.lib.makeBinPath [
            (pkgs.pass.withExtensions (exts: [ exts.pass-otp ])) # Password management
            pkgs.gnupg
            self'.packages.rofi
            pkgs.wl-clipboard
            # pkgs.xclip
            # pkgs.wtype
            pkgs.ydotool
            pkgs.bun
            pkgs.nodejs_latest
            pkgs.libnotify

            # Core utilities
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnused
            pkgs.which
          ];
        };
      };

      packages.rofi-checklist = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "rofi-checklist" ''
          exec ${pkgs.bun}/bin/bun run ${./checklist.ts} "$@"
        '';
        env = {
          # Ensure PATH includes all runtime inputs
          PATH = pkgs.lib.makeBinPath [
            self'.packages.rofi
            pkgs.bun
            pkgs.nodejs_latest
            pkgs.libnotify

            # Core utilities
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnused
            pkgs.which
          ];
        };
      };
    };
}
