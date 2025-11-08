{ self, ... }:
{
  flake.nixosModules.desktop =
    {
      pkgs,
      # lib,
      ...
    }:
    let
      # inherit (lib) getExe;
      selfpkgs = self.packages."${pkgs.system}";
    in
    {
      imports = [
        # Requirements
        self.nixosModules.terminal

        self.nixosModules.chromium
        self.nixosModules.firefox
        self.nixosModules.hyprland
        self.nixosModules.pipewire
        self.nixosModules.tuigreet

        self.nixosModules.extra_hjem
      ];

      environment.systemPackages = [
        selfpkgs.terminal
        pkgs.pcmanfm
      ];

      fonts.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        cm_unicode
      ];

      services.upower.enable = true;

      hardware = {
        bluetooth.enable = true;
        bluetooth.powerOnBoot = false;

        opengl = {
          enable = true;
          driSupport32Bit = true;
        };
      };
    };
}
