{ self, ... }:
{
  flake.nixosModules.desktop =
    {
      pkgs,
      lib,
      ...
    }:
    let
      inherit (lib) getExe;
      selfpkgs = self.packages."${pkgs.system}";
    in
    {
      imports = [
        # Requirements
        self.nixosModules.terminal

        self.nixosModules.wallpaper

        self.nixosModules.pipewire
        self.nixosModules.tuigreet
        self.nixosModules.firefox
        self.nixosModules.chromium

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

      preferences.keymap = {
        "SUPERCONTROL + S".exec = ''${getExe pkgs.grim} -l 0 - | ${pkgs.wl-clipboard}/bin/wl-copy'';

        "SUPERSHIFT + E".exec = ''
          ${pkgs.wl-clipboard}/bin/wl-paste | ${getExe pkgs.swappy} -f -
        '';

        "SUPERSHIFT + S".exec = ''
          ${getExe pkgs.grim} -g "$(${getExe pkgs.slurp} -w 0)" - \
          | ${pkgs.wl-clipboard}/bin/wl-copy
        '';

        "SUPER + RETURN".exec = "kitty";
      };

      home.programs.hyprland = true;
    };
}
