{
  flake.nixosModules.firefox =
    { pkgs, ... }:
    {
      programs.firefox.enable = true;

      impermanence.home.directories = [
        ".mozilla"
      ];

      impermanence.home.cache.directories = [
        ".cache/mozilla"
      ];

      preferences.keymap = {
        "SUPER + b".package = pkgs.firefox;
      };
    };
}
