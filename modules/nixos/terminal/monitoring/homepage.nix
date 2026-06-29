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
        filterAttrs
        mapAttrs
        mapAttrs'
        mapAttrsToList
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
        portainer = 9000;
        qbittorrent = 8088;
        mongo = 41275;
      };
      mkPublicUrl =
        subdomain: path:
        let
          host = if subdomain == null then publicBaseDomain else "${subdomain}.${publicBaseDomain}";
        in
        "https://${host}${path}";
      mkAnyUrl = port: path: "http://0.0.0.0:${toString port}${path}";
      mkMagicUrl = name: path: "http://${name}${if path == "" then "/" else path}";
      serviceEnabled = path: attrByPath (path ++ [ "enable" ]) false config;
      stackEnabled =
        name: attrByPath [ "services" "docker-compose-stacks" "stacks" name "enable" ] false config;
      localServices = {
        dashboard = {
          enable = cfg.enable;
          port = ports.dashboard;
          label = "Dashboard";
          icon = "mdi-view-dashboard";
          description = "Homepage on ${hostName} via local magic DNS";
        };
        cockpit = {
          enable = serviceEnabled [
            "services"
            "cockpit-managed"
          ];
          port = ports.cockpit;
          label = "Cockpit";
          icon = "mdi-monitor-dashboard";
          description = "Systemd services, journal logs, terminal, and host actions";
        };
        "acp-chat" = {
          enable = serviceEnabled [
            "services"
            "acp-chat"
          ];
          port = ports.acpChat;
          label = "ACP Chat";
          icon = "mdi-chat-processing";
          description = "Browser UI for local ACP agents";
        };
        mitmproxy = {
          enable = serviceEnabled [
            "services"
            "mitmproxy"
          ];
          port = ports.mitmproxy;
          label = "Mitmproxy";
          icon = "mdi-security";
          description = "On-demand HTTPS traffic analysis UI";
        };
        vpn = {
          enable = serviceEnabled [
            "services"
            "vpn-proxy"
          ];
          port = ports.vpn;
          label = "VPN Proxy";
          icon = "mdi-vpn";
          description = "SOCKS5/HTTP VPN proxy management";
        };
        cliproxyapi = {
          enable = serviceEnabled [
            "services"
            "cliproxyapi"
          ];
          port = ports.cliproxyapi;
          label = "CLIProxyAPI";
          icon = "mdi-api";
          path = "/management.html";
          description = "OpenAI-compatible API wrapping AI CLIs";
        };
        omniroute = {
          enable = serviceEnabled [
            "services"
            "omniroute"
          ];
          port = ports.omniroute;
          label = "OmniRoute";
          icon = "mdi-routes";
          description = "OpenAI-compatible AI gateway";
        };
        "cpa-usage" = {
          enable = serviceEnabled [
            "services"
            "cpa-usage-keeper"
          ];
          port = ports.cpaUsage;
          label = "CPA Usage Keeper";
          icon = "mdi-chart-line";
          description = "Persistent CLIProxyAPI usage analytics";
        };
        dokploy = {
          enable = serviceEnabled [
            "services"
            "dokploy"
          ];
          port = ports.dokploy;
          label = "Dokploy";
          icon = "mdi-docker";
          description = "Self-hosted deployment control plane";
        };
        portainer = {
          enable = stackEnabled "portainer";
          port = ports.portainer;
          label = "Portainer";
          icon = "mdi-docker";
          description = "Local Docker and Compose stack management";
        };
        qbittorrent = {
          enable = stackEnabled "gluetun-qbittorrent";
          port = ports.qbittorrent;
          label = "qBittorrent";
          icon = "mdi-download-network";
          description = "Torrent WebUI exposed only through Gluetun's network namespace";
        };
        mongo = {
          enable = attrByPath [
            "virtualisation"
            "oci-containers"
            "containers"
            "mongo-express"
            "autoStart"
          ] false config;
          port = ports.mongo;
          label = "MongoDB Admin";
          icon = "mdi-database";
          description = "Mongo Express database management";
        };
      };
      enabledLocalServices = filterAttrs (_name: service: service.enable) localServices;
      localMagicDnsPorts = mapAttrs (_name: service: service.port) enabledLocalServices;
      mkLocalServiceCard = name: service: {
        "${service.label} — local" = {
          icon = service.icon;
          href = mkMagicUrl name (service.path or "");
          description = service.description;
        };
      };
      localServiceCards = mapAttrsToList mkLocalServiceCard enabledLocalServices;
      mkLocalBookmark = name: service: {
        "${name}/" = [
          {
            icon = service.icon;
            href = mkMagicUrl name (service.path or "/");
          }
        ];
      };
      localBookmarks = mapAttrsToList mkLocalBookmark enabledLocalServices;
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
                  "Dashboard — any interface" = {
                    icon = "mdi-lan";
                    href = mkAnyUrl ports.dashboard "";
                    description = "Homepage bind address link for LAN/Tailscale checks";
                  };
                }
              ]
              ++ localServiceCards;
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
                  "Portainer" = {
                    icon = "mdi-docker";
                    href = mkPublicUrl "portainer" "";
                    description = "Docker management UI protected by shared auth";
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
              "Short local names" = localBookmarks;
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

        # Homepage-local magic DNS stays host-scoped: enabled dashboard service names resolve
        # to loopback and proxy from port 80 to their original localhost-bound ports.
        networking.hosts."127.0.0.1" = builtins.attrNames localMagicDnsPorts;

        services.nginx = mkIf (!traefikEnabled) {
          enable = true;
          virtualHosts = mapAttrs (name: service: {
            serverName = name;
            listen = [
              {
                addr = "127.0.0.1";
                port = 80;
              }
            ];
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString service.port}";
              recommendedProxySettings = true;
              proxyWebsockets = true;
              extraConfig = ''
                proxy_buffering off;
                proxy_request_buffering off;
                proxy_redirect http://127.0.0.1:${toString service.port}/ http://$host/;
                proxy_redirect http://localhost:${toString service.port}/ http://$host/;
                proxy_cookie_domain 127.0.0.1 $host;
                proxy_cookie_domain localhost $host;
                proxy_cookie_path / /;
                proxy_hide_header Cross-Origin-Embedder-Policy;
                proxy_hide_header Cross-Origin-Opener-Policy;
                proxy_hide_header Cross-Origin-Resource-Policy;
              '';
            };
          }) enabledLocalServices;
        };

        services.traefik.dynamicConfigOptions.http = mkIf traefikEnabled {
          routers = mapAttrs' (
            name: service:
            nameValuePair (mkTraefikRouterName name) {
              rule = "Host(`${name}`)";
              service = mkTraefikServiceName name;
              entryPoints = [ "web" ];
              middlewares = [ "${mkTraefikRouterName name}-headers" ];
            }
          ) enabledLocalServices;
          services = mapAttrs' (
            name: service:
            nameValuePair (mkTraefikServiceName name) {
              loadBalancer.servers = [
                { url = "http://127.0.0.1:${toString service.port}"; }
              ];
            }
          ) enabledLocalServices;
          middlewares = mapAttrs' (
            name: _service:
            nameValuePair "${mkTraefikRouterName name}-headers" {
              # Magic DNS is an HTTP-only shortcut; qBittorrent emits COOP/COEP headers
              # that browsers ignore on non-trustworthy origins and can stall app startup.
              # Empty Traefik response header values remove the upstream header.
              # Source: https://doc.traefik.io/traefik/middlewares/http/headers/
              headers.customResponseHeaders = {
                Cross-Origin-Embedder-Policy = "";
                Cross-Origin-Opener-Policy = "";
                Cross-Origin-Resource-Policy = "";
              };
            }
          ) enabledLocalServices;
        };
      };
    };
}
