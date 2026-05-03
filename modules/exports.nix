{ self, ... }:
let
  # Read nested option paths from evaluated host config safely.
  # Why: matrix generation should reflect actual effective options, not duplicated host lists.
  attrByPathOr =
    path: fallback: attrs:
    if path == [ ] then
      attrs
    else
      let
        key = builtins.head path;
        rest = builtins.tail path;
      in
      if builtins.isAttrs attrs && builtins.hasAttr key attrs then
        attrByPathOr rest fallback attrs.${key}
      else
        fallback;

  enabledBySelectors =
    hostConfig: selectors:
    builtins.filter (name: attrByPathOr selectors.${name} false hostConfig == true) (
      builtins.attrNames selectors
    );

  # Keep tracked capabilities in one place so rebuild.sh rendering stays modular.
  # Source for option surface: README "Modular Host Composition" + modules/hosts/*/configuration.nix.
  matrixSelectors = {
    profiles = {
      desktop = [
        "preferences"
        "profiles"
        "desktop"
        "enable"
      ];
      laptop = [
        "preferences"
        "profiles"
        "laptop"
        "enable"
      ];
      server = [
        "preferences"
        "profiles"
        "server"
        "enable"
      ];
      terminal = [
        "preferences"
        "profiles"
        "terminal"
        "enable"
      ];
    };

    features = {
      obs = [
        "preferences"
        "obs"
        "enable"
      ];
      tlp = [
        "preferences"
        "hardware"
        "tlp"
        "enable"
      ];
    };

    services = {
      cliproxyapi = [
        "services"
        "cliproxyapi"
        "enable"
      ];
      cpa-usage-keeper = [
        "services"
        "cpa-usage-keeper"
        "enable"
      ];
      dokploy = [
        "services"
        "dokploy"
        "enable"
      ];
      homepage-monitor = [
        "services"
        "homepage-monitor"
        "enable"
      ];
      hypridle = [
        "services"
        "hypridle"
        "enable"
      ];
      mitmproxy = [
        "services"
        "mitmproxy"
        "enable"
      ];
      netdata-monitor = [
        "services"
        "netdata-monitor"
        "enable"
      ];
      unison-sync = [
        "services"
        "unison-sync"
        "enable"
      ];
      vpn-proxy = [
        "services"
        "vpn-proxy"
        "enable"
      ];
    };

    programs = { };
  };

  mkHostMatrix = hostConfig: {
    profiles = enabledBySelectors hostConfig matrixSelectors.profiles;
    features = enabledBySelectors hostConfig matrixSelectors.features;
    services = enabledBySelectors hostConfig matrixSelectors.services;
    programs = enabledBySelectors hostConfig matrixSelectors.programs;
  };

  # rebuild.sh consumes this attr via `nix eval --json path:.#hostModuleMatrix`.
  hostModuleMatrix = builtins.mapAttrs (
    _host: nixosConfig: mkHostMatrix nixosConfig.config
  ) self.nixosConfigurations;
in
{
  flake = {
    inherit hostModuleMatrix;

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
        dankmemershell = self.nixosModules.dankmemershell;
        hyprland = self.nixosModules.hyprland;
        hyprland-support = self.nixosModules.hyprland-support;
        obs = self.nixosModules.obs;
        qt = self.nixosModules.qt;
        syncthing = self.nixosModules.syncthing;
        tlp = self.nixosModules.tlp;
        tuigreet = self.nixosModules.tuigreet;
        vscodium = self.nixosModules.vscodium;
      };

      services = {
        cliproxyapi = self.nixosModules.cliproxyapi;
        cpa-usage-keeper = self.nixosModules.cpa-usage-keeper;
        services-auth-gateway = self.nixosModules.services-auth-gateway;
        dev = self.nixosModules.dev;
        homepage-monitor = self.nixosModules.homepage-monitor;
        mitmproxy = self.nixosModules.mitmproxy;
        netdata-monitor = self.nixosModules.netdata-monitor;
        nix = self.nixosModules.nix;
        opencode = self.nixosModules.opencode;
        tailscale = self.nixosModules.tailscale;
        unison = self.nixosModules.unison;
        virtualisation = self.nixosModules.virtualisation;
        vpn-proxy-service = self.nixosModules.vpn-proxy-service;
      };

      hosts = {
        main_vps = self.nixosModules.main_vpsHost;
        legion5i = self.nixosModules.legion5iHost;
        macbook = self.nixosModules.macbookHost;
      };
    };
  };
}
