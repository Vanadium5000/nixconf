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
      packages.passmenu = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.writeShellScriptBin "passmenu" ''
          exec ${pkgs.bun}/bin/bun run ${./passmenu.ts} "$@"
        '';
        runtimeInputs = [
          # Required packages
          pkgs.pass
          pkgs.gnupg
          self'.packages.rofi
          pkgs.wl-clipboard
          pkgs.wtype
          pkgs.ydotool
          pkgs.bun

          # Core utilities needed by the script
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnused
          pkgs.which
        ];
        env = {
          # Ensure PATH includes all runtime inputs
          PATH = pkgs.lib.makeBinPath [
            pkgs.pass
            pkgs.gnupg
            self'.packages.rofi
            pkgs.wl-clipboard
            # pkgs.wtype
            pkgs.ydotool
            pkgs.bun

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
