{ self, ... }:
let
in
{
  flake = {
    moduleSets = {
      profiles = {
        common = self.nixosModules.common;
        desktop = self.nixosModules.desktop;
        extra_hjem = self.nixosModules.extra_hjem;
        terminal = self.nixosModules.terminal;
      };

      features = {
        audio = self.nixosModules.audio;
        bluetooth = self.nixosModules.bluetooth;
        firefox = self.nixosModules.firefox;
        hyprland = self.nixosModules.hyprland;
        hyprland-support = self.nixosModules.hyprland-support;
        hyprsunset = self.nixosModules.hyprsunset;
        obs = self.nixosModules.obs;
        qt = self.nixosModules.qt;
        syncthing = self.nixosModules.syncthing;
        tlp = self.nixosModules.tlp;
        tuigreet = self.nixosModules.tuigreet;
        vscodium = self.nixosModules.vscodium;
      };

      services = {
        cliproxyapi = self.nixosModules.cliproxyapi;
        dev = self.nixosModules.dev;
        homepage-monitor = self.nixosModules.homepage-monitor;
        mitmproxy = self.nixosModules.mitmproxy;
        netdata-monitor = self.nixosModules.netdata-monitor;
        nix = self.nixosModules.nix;
        opencode = self.nixosModules.opencode;
        openclaw = self.nixosModules.openclaw;
        tailscale = self.nixosModules.tailscale;
        unison = self.nixosModules.unison;
        virtualisation = self.nixosModules.virtualisation;
        vpn-proxy-service = self.nixosModules.vpn-proxy-service;
      };

      hosts = {
        ionos_vps = self.nixosModules.ionos_vpsHost;
        legion5i = self.nixosModules.legion5iHost;
        macbook = self.nixosModules.macbookHost;
      };
    };
  };
}
