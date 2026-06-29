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
      obsidian = [
        "preferences"
        "obsidian"
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
      bifrost = [
        "services"
        "bifrost"
        "enable"
      ];
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
      omniroute = [
        "services"
        "omniroute"
        "enable"
      ];
      dokploy = [
        "services"
        "dokploy"
        "enable"
      ];
      docker-compose-stacks = [
        "services"
        "docker-compose-stacks"
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
      cockpit = [
        "services"
        "cockpit-managed"
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
        terminal = self.nixosModules.terminal;
      };

      features = {
        audio = self.nixosModules.audio;
        bluetooth = self.nixosModules.bluetooth;
        hdmi-cec = self.nixosModules.hdmi-cec;
        firefox = self.nixosModules.firefox;
        dankmemershell = self.nixosModules.dankmemershell;
        hyprland = self.nixosModules.hyprland;
        hyprland-support = self.nixosModules.hyprland-support;
        obs = self.nixosModules.obs;
        obsidian = self.nixosModules.obsidian;
        qt = self.nixosModules.qt;
        syncthing = self.nixosModules.syncthing;
        tlp = self.nixosModules.tlp;
        tuigreet = self.nixosModules.tuigreet;
        vscodium = self.nixosModules.vscodium;
      };

      services = {
        bifrost = self.nixosModules.bifrost;
        cliproxyapi = self.nixosModules.cliproxyapi;
        cpa-usage-keeper = self.nixosModules.cpa-usage-keeper;
        omniroute = self.nixosModules.omniroute;
        services-auth-gateway = self.nixosModules.services-auth-gateway;
        dev = self.nixosModules.dev;
        docker-compose-stacks = self.nixosModules.docker-compose-stacks;
        homepage-monitor = self.nixosModules.homepage-monitor;
        mitmproxy = self.nixosModules.mitmproxy;
        netdata-monitor = self.nixosModules.netdata-monitor;
        nix = self.nixosModules.nix;
        opencode = self.nixosModules.opencode;
        omp = self.nixosModules.omp;
        tailscale = self.nixosModules.tailscale;
        unison = self.nixosModules.unison;
        virtualisation = self.nixosModules.virtualisation;
        vpn-proxy-service = self.nixosModules.vpn-proxy-service;
        cockpit = self.nixosModules.cockpit;
      };

      hosts = {
        main_vps = self.nixosModules.main_vpsHost;
        legion5i = self.nixosModules.legion5iHost;
        macbook = self.nixosModules.macbookHost;
      };
    };
  };
}
