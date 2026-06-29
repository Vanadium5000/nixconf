# Homepage — declarative fleet dashboard portal
# Central web UI showing system metrics, service links, and bookmarks.
# Fully declarative (zero state) — survives ephemeral root without persistence.
# Access via Tailscale: http://<hostname>:8082
#
# Tailscale MagicDNS hostnames are used for cross-host links.
# Verify your hostnames with: tailscale status
# Note: underscores in hostnames are typically converted to hyphens by MagicDNS
# (for example, server_host → server-host)
{ self, ... }:
{
  flake.nixosModules.homepage-monitor =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (lib)
        attrByPath
        mapAttrs
        mapAttrs'
        nameValuePair
        mkEnableOption
        mkOption
        mkIf
        types
        ;
      cfg = config.services.homepage-monitor;
      publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;
      hostName = attrByPath [ "preferences" "hostName" ] "localhost" config;
      portOf = path: fallback: attrByPath path fallback config;
      traefikEnabled = attrByPath [ "services" "traefik" "enable" ] false config;
      ports = {
        dashboard = cfg.port;
        cockpit = portOf [ "services" "cockpit-managed" "port" ] 9090;
        acpChat = portOf [ "services" "acp-chat" "port" ] 8732;
        mitmproxy = portOf [ "services" "mitmproxy" "webPort" ] 8083;
        vpn = portOf [ "services" "vpn-proxy" "webUiPort" ] 10802;
        cliproxyapi = portOf [ "services" "cliproxyapi" "port" ] 8317;
        omniroute = portOf [ "services" "omniroute" "port" ] 20128;
        cpaUsage = portOf [ "services" "cpa-usage-keeper" "port" ] 8080;
        dokploy = portOf [ "services" "dokploy" "port" ] 3000;
        mongo = 41275;
      };
      mkPublicUrl =
        subdomain: path:
        let
          host = if subdomain == null then publicBaseDomain else "${subdomain}.${publicBaseDomain}";
        in
        "https://${host}${path}";
      mkLocalUrl = port: path: "http://localhost:${toString port}${path}";
      mkAnyUrl = port: path: "http://0.0.0.0:${toString port}${path}";
      mkShortUrl =
        name: port: path:
        "http://${name}:${toString port}${path}";
      shortHostnames = {
        dashboard = ports.dashboard;
        cockpit = ports.cockpit;
        "acp-chat" = ports.acpChat;
        mitmproxy = ports.mitmproxy;
        vpn = ports.vpn;
        cliproxyapi = ports.cliproxyapi;
        omniroute = ports.omniroute;
        "cpa-usage" = ports.cpaUsage;
        dokploy = ports.dokploy;
        mongo = ports.mongo;
      };
      mkTraefikServiceName = name: "local-${name}";
      mkTraefikRouterName = name: "local-${name}";
    in
    {
      options.services.homepage-monitor = {
        enable = mkEnableOption "Homepage fleet dashboard portal" // {
          default = true;
        };

        port = mkOption {
          type = types.port;
          default = 8082;
          description = ''
            Port for the Homepage dashboard.
            Avoids conflicts: 3000=dokploy, 41275=mongo-express,
            8317=cliproxyapi.
          '';
        };

        openFirewall = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to open the dashboard port in the firewall.
            Not needed when Tailscale's trustedInterfaces is configured —
            traffic over tailscale0 already bypasses the firewall.
          '';
        };
      };

      config = mkIf cfg.enable {
        services.homepage-dashboard = {
          enable = true;
          listenPort = cfg.port;

          allowedHosts = "*";
          customCSS = ''
            :root {
              --color-800: 15 23 42;
              --color-900: 2 6 23;
              --color-950: 2 6 23;
            }

            body {
              background:
                radial-gradient(circle at top left, rgba(14, 165, 233, 0.16), transparent 28rem),
                radial-gradient(circle at bottom right, rgba(168, 85, 247, 0.14), transparent 30rem),
                rgb(2, 6, 23);
            }

            #information-widgets, .service-card {
              backdrop-filter: blur(18px);
            }
          '';

          settings = {
            title = "NixOS Fleet — ${hostName}";
            theme = "dark";
            color = "slate";
            headerStyle = "boxed";
            statusStyle = "dot";
            layout = {
              "Local on this host" = {
                style = "row";
                columns = 4;
              };
              "Public dashboards" = {
                style = "row";
                columns = 4;
              };
              "Developer references" = {
                style = "row";
                columns = 3;
              };
            };
            useEqualHeights = true;
          };

          widgets = [
            {
              resources = {
                cpu = true;
                memory = true;
                disk = "/";
                label = "System";
              };
            }
            {
              datetime = {
                text_size = "xl";
                format = {
                  dateStyle = "short";
                  timeStyle = "short";
                  hour12 = false;
                };
              };
            }
            {
              search = {
                provider = "duckduckgo";
                target = "_blank";
              };
            }
          ];

          services = [
            {
              "Local on this host" = [
                {
                  "Dashboard — local" = {
                    icon = "mdi-view-dashboard";
                    href = mkLocalUrl ports.dashboard "";
                    description = "Homepage on ${hostName} via localhost";
                  };
                }
                {
                  "Dashboard — any interface" = {
                    icon = "mdi-lan";
                    href = mkAnyUrl ports.dashboard "";
                    description = "Homepage bind address link for LAN/Tailscale checks";
                  };
                }
                {
                  "Cockpit — local" = {
                    icon = "mdi-monitor-dashboard";
                    href = mkLocalUrl ports.cockpit "";
                    description = "Systemd services, journal logs, terminal, and host actions";
                  };
                }
                {
                  "ACP Chat — local" = {
                    icon = "mdi-chat-processing";
                    href = mkLocalUrl ports.acpChat "";
                    description = "Browser UI for local ACP agents";
                  };
                }
                {
                  "Mitmproxy — local" = {
                    icon = "mdi-security";
                    href = mkLocalUrl ports.mitmproxy "";
                    description = "On-demand HTTPS traffic analysis UI";
                  };
                }
                {
                  "VPN Proxy — local" = {
                    icon = "mdi-vpn";
                    href = mkLocalUrl ports.vpn "";
                    description = "SOCKS5/HTTP VPN proxy management";
                  };
                }
              ];
            }
            {
              "Public dashboards" = [
                {
                  "Dashboard" = {
                    icon = "mdi-view-dashboard";
                    href = mkPublicUrl "dashboard" "";
                    description = "Authenticated public fleet dashboard";
                  };
                }
                {
                  "Cockpit" = {
                    icon = "mdi-monitor-dashboard";
                    href = mkPublicUrl "cockpit" "";
                    description = "Public Cockpit route protected by shared auth";
                  };
                }
                {
                  "CLIProxyAPI" = {
                    icon = "mdi-api";
                    href = mkPublicUrl "cliproxyapi" "/management.html";
                    description = "OpenAI-compatible API wrapping AI CLIs";
                  };
                }
                {
                  "OmniRoute" = {
                    icon = "mdi-routes";
                    href = mkPublicUrl "omniroute" "";
                    description = "OpenAI-compatible AI gateway";
                  };
                }
                {
                  "CPA Usage Keeper" = {
                    icon = "mdi-chart-line";
                    href = mkPublicUrl "cpa-usage" "";
                    description = "Persistent CLIProxyAPI usage analytics";
                  };
                }
                {
                  "Dokploy" = {
                    icon = "mdi-docker";
                    href = mkPublicUrl "dokploy" "";
                    description = "Self-hosted deployment control plane";
                  };
                }
                {
                  "VPN Proxy" = {
                    icon = "mdi-vpn";
                    href = mkPublicUrl "vpn" "";
                    description = "Public VPN proxy management route";
                  };
                }
                {
                  "MongoDB Admin" = {
                    icon = "mdi-database";
                    href = mkPublicUrl "mongo" "";
                    description = "Mongo Express database management";
                  };
                }
                {
                  "My Website" = {
                    icon = "mdi-web";
                    href = mkPublicUrl null "";
                    description = "Primary website";
                  };
                }
              ];
            }
            {
              "Developer references" = [
                {
                  "NixOS Packages" = {
                    icon = "mdi-magnify";
                    href = "https://search.nixos.org/packages";
                    description = "Search nixpkgs packages";
                  };
                }
                {
                  "NixOS Options" = {
                    icon = "mdi-cog";
                    href = "https://search.nixos.org/options";
                    description = "Search NixOS module options";
                  };
                }
                {
                  "Nix Reference Manual" = {
                    icon = "mdi-book-open-variant";
                    href = "https://nix.dev/manual/nix/latest/";
                    description = "Nix language and command reference";
                  };
                }
              ];
            }
          ];

          bookmarks = [
            {
              "Short local names" = [
                {
                  "dashboard/" = [
                    {
                      icon = "mdi-view-dashboard";
                      href = mkShortUrl "dashboard" ports.dashboard "";
                    }
                  ];
                }
                {
                  "cockpit/" = [
                    {
                      icon = "mdi-monitor-dashboard";
                      href = mkShortUrl "cockpit" ports.cockpit "";
                    }
                  ];
                }
                {
                  "acp-chat/" = [
                    {
                      icon = "mdi-chat-processing";
                      href = mkShortUrl "acp-chat" ports.acpChat "";
                    }
                  ];
                }
                {
                  "mitmproxy/" = [
                    {
                      icon = "mdi-security";
                      href = mkShortUrl "mitmproxy" ports.mitmproxy "";
                    }
                  ];
                }
                {
                  "vpn/" = [
                    {
                      icon = "mdi-vpn";
                      href = mkShortUrl "vpn" ports.vpn "";
                    }
                  ];
                }
              ];
            }
            {
              "Fleet" = [
                {
                  "Cockpit — Legion 5i" = [
                    {
                      icon = "mdi-laptop";
                      href = "http://legion5i:${toString ports.cockpit}";
                    }
                  ];
                }
                {
                  "Cockpit — MacBook" = [
                    {
                      icon = "mdi-laptop";
                      href = "http://macbook:${toString ports.cockpit}";
                    }
                  ];
                }
                {
                  "Dashboard — Legion 5i" = [
                    {
                      icon = "mdi-view-dashboard";
                      href = "http://legion5i:${toString ports.dashboard}";
                    }
                  ];
                }
                {
                  "Dashboard — MacBook" = [
                    {
                      icon = "mdi-view-dashboard";
                      href = "http://macbook:${toString ports.dashboard}";
                    }
                  ];
                }
              ];
            }
          ];
        };

        networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

        # Short dashboard names resolve locally on every host; browsers can open
        # http://dashboard/, http://cockpit/, etc. without leaking these names to DNS.
        networking.hosts."127.0.0.1" = builtins.attrNames shortHostnames;

        services.nginx = mkIf (!traefikEnabled) {
          enable = true;
          virtualHosts = mapAttrs (name: port: {
            serverName = name;
            listen = [
              {
                addr = "127.0.0.1";
                port = 80;
              }
            ];
            locations."/".proxyPass = "http://127.0.0.1:${toString port}";
          }) shortHostnames;
        };

        services.traefik.dynamicConfigOptions.http = mkIf traefikEnabled {
          routers = mapAttrs' (
            name: _:
            nameValuePair (mkTraefikRouterName name) {
              rule = "Host(`${name}`)";
              service = mkTraefikServiceName name;
              entryPoints = [ "web" ];
            }
          ) shortHostnames;
          services = mapAttrs (_name: port: {
            loadBalancer.servers = [
              { url = "http://127.0.0.1:${toString port}"; }
            ];
          }) shortHostnames;
        };
      };
    };
}
