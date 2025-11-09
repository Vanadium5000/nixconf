{
  flake.nixosModules.bluetooth =
    { pkgs, ... }:
    {
      # Bluetooth support
      hardware.bluetooth = {
        enable = true; # Whether to enable support for Bluetooth
        powerOnBoot = false; # Whether to power up the default Bluetooth controller on boot
      };

      services.blueman.enable = true; # GTK-based Bluetooth Manager
      environment.systemPackages = with pkgs; [ blueman ];
    };
}
