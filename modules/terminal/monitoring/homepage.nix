# Homepage — declarative fleet dashboard portal
# Central web UI showing system metrics, service links, and bookmarks.
# Fully declarative (zero state) — survives ephemeral root without persistence.
# Access via Tailscale: http://<hostname>:8082  or magic DNS http://dashboard/
#
# Single service catalog drives local cards, public cards, magic DNS, nginx/traefik
# proxies, and bookmarks so ports/icons/descriptions stay consistent.
#
# Upstream: https://gethomepage.dev/configs/
# Tailscale MagicDNS: underscores in hostnames become hyphens (server_host → server-host)
{ self, ... }:
{
  flake.nixosModules.homepage-monitor =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        attrByPath
        concatMap
        filterAttrs
        mapAttrs
        mapAttrs'
        nameValuePair
        mkEnableOption
        mkOption
        mkIf
        optional
        types
        unique
        ;
      cfg = config.services.homepage-monitor;
      publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;
      hostName = attrByPath [ "preferences" "hostName" ] "localhost" config;
      portOf = path: fallback: attrByPath path fallback config;
      traefikEnabled = attrByPath [ "services" "traefik" "enable" ] false config;
      secrets = self.secrets or { };
      theme = self.themes.mainTheme;
      inherit (theme)
        colors
        palette
        glass
        settings
        ;
      rgba = self.themes.toRgba;
      rgb = self.themes.toRgb;

      # Homepage supports mdi/si icon colour suffixes. Derive them from the
      # active typed theme rather than coupling this module to one palette.
      # Source: https://gethomepage.dev/configs/services/#icons
      c = {
        cyan = colors.base0C;
        magenta = colors.base0E;
        violet = colors.base0D;
        lime = colors.base0B;
        amber = colors.base0A;
        rose = colors.base08;
        blue = colors.base0D;
        sky = colors.base0C;
        emerald = colors.base0B;
        orange = colors.base09;
        white = colors.base07;
      };

      ports = {
        dashboard = cfg.port;
        docs = portOf [ "services" "nixconf-docs" "port" ] 8090;
        cockpit = portOf [ "services" "cockpit-managed" "port" ] 9090;
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
      mkMagicUrl = name: path: "http://${name}${if path == "" then "/" else path}";
      # Uniform port badge for every card/bookmark description.
      withPort = description: port: "${description} · :${toString port}";
      serviceEnabled = path: attrByPath (path ++ [ "enable" ]) false config;
      stackEnabled =
        name: attrByPath [ "services" "docker-compose-stacks" "stacks" name "enable" ] false config;

      # Catalog entries:
      # - local: magic-DNS name on this host when enable
      # - public: edge subdomain card (always listed; routes live on main_vps)
      # - path: optional href suffix
      # - widget: optional Homepage service widget attrset
      serviceCatalog = {
        dashboard = {
          enable = cfg.enable;
          port = ports.dashboard;
          label = "Dashboard";
          icon = "mdi-view-dashboard-${c.cyan}";
          description = "Homepage fleet portal";
          publicSubdomain = "dashboard";
          publicDescription = "Authenticated public fleet dashboard";
        };
        cockpit = {
          enable = serviceEnabled [
            "services"
            "cockpit-managed"
          ];
          port = ports.cockpit;
          label = "Cockpit";
          icon = "mdi-monitor-dashboard-${c.sky}";
          description = "Systemd, journals, terminal, host actions";
          publicSubdomain = "cockpit";
          publicDescription = "Public Cockpit route (shared auth)";
        };
        docs = {
          enable = serviceEnabled [
            "services"
            "nixconf-docs"
          ];
          port = ports.docs;
          label = "Docs";
          icon = "mdi-book-open-page-variant-${c.violet}";
          description = "Generated Nixconf fleet documentation";
          publicSubdomain = "docs";
          publicDescription = "Generated Nixconf fleet documentation";
        };
        # Magic name must be >=4 chars: Elysia/Bun returns NOT_FOUND for short
        # Host headers (e.g. "vpn"), so the UI login succeeds then all /api/* fail
        # through nginx magic DNS. Source: observed Host length < 4 → NOT_FOUND.
        "vpn-proxy" = {
          enable = serviceEnabled [
            "services"
            "vpn-proxy"
          ];
          port = ports.vpn;
          label = "VPN Proxy";
          icon = "mdi-vpn-${c.lime}";
          description = "SOCKS5/HTTP VPN proxy management";
          publicSubdomain = "vpn";
          publicDescription = "Public VPN proxy management route";
        };
        cliproxyapi = {
          enable = serviceEnabled [
            "services"
            "cliproxyapi"
          ];
          port = ports.cliproxyapi;
          label = "CLIProxyAPI";
          icon = "mdi-api-${c.cyan}";
          path = "/management.html";
          description = "OpenAI-compatible API wrapping AI CLIs";
          publicSubdomain = "cliproxyapi";
          publicDescription = "OpenAI-compatible API wrapping AI CLIs";
        };
        omniroute = {
          enable = serviceEnabled [
            "services"
            "omniroute"
          ];
          port = ports.omniroute;
          label = "OmniRoute";
          icon = "mdi-routes-${c.violet}";
          description = "OpenAI-compatible AI gateway";
          publicSubdomain = "omniroute";
          publicDescription = "OpenAI-compatible AI gateway";
        };
        "cpa-usage" = {
          enable = serviceEnabled [
            "services"
            "cpa-usage-keeper"
          ];
          port = ports.cpaUsage;
          label = "CPA Usage Keeper";
          icon = "mdi-chart-timeline-variant-${c.amber}";
          description = "Persistent CLIProxyAPI usage analytics";
          publicSubdomain = "cpa-usage";
          publicDescription = "Persistent CLIProxyAPI usage analytics";
        };
        dokploy = {
          enable = serviceEnabled [
            "services"
            "dokploy"
          ];
          port = ports.dokploy;
          label = "Dokploy";
          icon = "mdi-rocket-launch-${c.orange}";
          description = "Self-hosted deployment control plane";
          publicSubdomain = "dokploy";
          publicDescription = "Self-hosted deployment control plane";
        };
        portainer = {
          enable = stackEnabled "portainer";
          port = ports.portainer;
          label = "Portainer";
          # Dashboard Icons CDN brand mark.
          # Source: https://github.com/homarr-labs/dashboard-icons
          icon = "portainer.png";
          description = "Docker and Compose stack management";
          publicSubdomain = "portainer";
          publicDescription = "Docker management UI (shared auth)";
          # env is the Portainer endpoint id from #!/endpoints/<id>.
          # Source: https://gethomepage.dev/widgets/services/portainer/
          widget = {
            type = "portainer";
            url = "http://127.0.0.1:${toString ports.portainer}";
            env = cfg.portainerEnv;
            key = "{{HOMEPAGE_VAR_PORTAINER_KEY}}";
            fields = [
              "running"
              "stopped"
              "total"
            ];
          };
        };
        qbittorrent = {
          enable = stackEnabled "gluetun-qbittorrent";
          port = ports.qbittorrent;
          label = "qBittorrent";
          icon = "qbittorrent.png";
          description = "Torrent WebUI via Gluetun network namespace";
          public = false;
          # Source: https://gethomepage.dev/widgets/services/qbittorrent/
          widget = {
            type = "qbittorrent";
            url = "http://127.0.0.1:${toString ports.qbittorrent}";
            username = "{{HOMEPAGE_VAR_QBITTORRENT_USERNAME}}";
            password = "{{HOMEPAGE_VAR_QBITTORRENT_PASSWORD}}";
            enableLeechProgress = true;
            fields = [
              "leech"
              "download"
              "seed"
              "upload"
            ];
          };
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
          icon = "mdi-database-${c.emerald}";
          description = "Mongo Express database management";
          publicSubdomain = "mongo";
          publicDescription = "Mongo Express database management";
        };
      };

      enabledLocalServices = filterAttrs (_name: service: service.enable or false) serviceCatalog;

      # Stable public edge order (catalog keys). Always listed; edge lives on main_vps.
      publicServiceOrder = [
        "dashboard"
        "docs"
        "cockpit"
        "cliproxyapi"
        "omniroute"
        "cpa-usage"
        "dokploy"
        "portainer"
        "vpn-proxy"
        "mongo"
      ];
      publicServices = concatMap (
        name:
        let
          service = serviceCatalog.${name};
        in
        optional (service.public or true) {
          inherit name;
          inherit (service) label icon port;
          subdomain = service.publicSubdomain or name;
          path = service.path or "";
          description = service.publicDescription or service.description;
        }
      ) publicServiceOrder;

      websitePublic = {
        name = "website";
        label = "My Website";
        icon = "mdi-web-${c.cyan}";
        port = 443;
        subdomain = null;
        path = "";
        description = "Primary website apex";
      };

      mkServiceCard =
        {
          title,
          icon,
          href,
          description,
          port,
          widget ? null,
          siteMonitor ? null,
        }:
        {
          ${title} = {
            inherit icon href;
            description = withPort description port;
          }
          // lib.optionalAttrs (widget != null) { widget = widget; }
          // lib.optionalAttrs (siteMonitor != null) { siteMonitor = siteMonitor; };
        };

      mkLocalServiceCard =
        name: service:
        mkServiceCard {
          title = service.label;
          icon = service.icon;
          href = mkMagicUrl name (service.path or "");
          description = service.description;
          port = service.port;
          widget = service.widget or null;
          siteMonitor = "http://127.0.0.1:${toString service.port}${service.path or ""}";
        };

      # Stable local card order (enabled subset only).
      localServiceOrder = [
        "dashboard"
        "docs"
        "cockpit"
        "portainer"
        "qbittorrent"
        "vpn-proxy"
        "cliproxyapi"
        "omniroute"
        "cpa-usage"
        "dokploy"
        "mongo"
      ];
      localServiceCards = concatMap (
        name:
        if enabledLocalServices ? ${name} then
          [ (mkLocalServiceCard name enabledLocalServices.${name}) ]
        else
          [ ]
      ) localServiceOrder;

      publicServiceCards = map (
        service:
        mkServiceCard {
          title = service.label;
          icon = service.icon;
          href = mkPublicUrl service.subdomain (service.path or "");
          description = service.description;
          port = service.port;
          siteMonitor = null;
        }
      ) (publicServices ++ [ websitePublic ]);

      fleetHosts = [
        {
          id = "legion5i";
          label = "Legion 5i";
        }
        {
          id = "macbook";
          label = "MacBook";
        }
        {
          id = "main-vps";
          label = "Main VPS";
        }
      ];

      fleetServices = [
        {
          key = "dashboard";
          label = "Dashboard";
          icon = "mdi-view-dashboard-${c.cyan}";
          port = ports.dashboard;
        }
        {
          key = "docs";
          label = "Docs";
          icon = "mdi-book-open-page-variant-${c.violet}";
          port = ports.docs;
        }
        {
          key = "cockpit";
          label = "Cockpit";
          icon = "mdi-monitor-dashboard-${c.sky}";
          port = ports.cockpit;
        }
        {
          key = "portainer";
          label = "Portainer";
          icon = "portainer.png";
          port = ports.portainer;
        }
      ];

      fleetBookmarks = concatMap (
        host:
        map (svc: {
          "${svc.label} — ${host.label}" = [
            {
              icon = svc.icon;
              href = "http://${host.id}:${toString svc.port}";
              # Bookmarks have no description field; encode port in abbr.
              abbr = ":${toString svc.port}";
            }
          ];
        }) fleetServices
      ) fleetHosts;

      developerCards = [
        (mkServiceCard {
          title = "NixOS Packages";
          icon = "si-nixos-${c.sky}";
          href = "https://search.nixos.org/packages";
          description = "Search nixpkgs packages";
          port = 443;
        })
        (mkServiceCard {
          title = "NixOS Options";
          icon = "si-nixos-${c.violet}";
          href = "https://search.nixos.org/options";
          description = "Search NixOS module options";
          port = 443;
        })
        (mkServiceCard {
          title = "Nix Reference Manual";
          icon = "mdi-book-open-variant-${c.cyan}";
          href = "https://nix.dev/manual/nix/latest/";
          description = "Nix language and command reference";
          port = 443;
        })
        (mkServiceCard {
          title = "Homepage Docs";
          icon = "mdi-view-dashboard-edit-${c.magenta}";
          href = "https://gethomepage.dev/";
          description = "Upstream dashboard configuration reference";
          port = 443;
        })
      ];

      localMagicDnsPorts = mapAttrs (_name: service: service.port) enabledLocalServices;
      mkTraefikServiceName = name: "local-${name}";
      mkTraefikRouterName = name: "local-${name}";

      # Homepage only substitutes HOMEPAGE_VAR_* / HOMEPAGE_FILE_* env placeholders.
      # Source: https://gethomepage.dev/installation/docker/#using-environment-secrets
      homepageEnvironmentFile = pkgs.writeText "homepage-dashboard.env" ''
        HOMEPAGE_VAR_PORTAINER_KEY=${secrets.PORTAINER_API_KEY or ""}
        HOMEPAGE_VAR_QBITTORRENT_USERNAME=${secrets.QBITTORRENT_WEBUI_USERNAME or ""}
        HOMEPAGE_VAR_QBITTORRENT_PASSWORD=${secrets.QBITTORRENT_WEBUI_PASSWORD or ""}
      '';

      # This stylesheet consumes only the typed theme contract; selecting a
      # different registry entry rethemes Homepage without a CSS fork.
      homepageCSS = ''
        :root {
          --color-50: ${rgb colors.base07};
          --color-100: ${rgb colors.base06};
          --color-200: ${rgb colors.base05};
          --color-300: ${rgb colors.base04};
          --color-400: ${rgb colors.base0C};
          --color-500: ${rgb palette.accentAlt};
          --color-600: ${rgb palette.accent};
          --color-700: ${rgb colors.base0D};
          --color-800: ${rgb colors.base01};
          --color-900: ${rgb colors.base00};
          --color-950: ${rgb colors.base00};

          --nixconf-bg: ${palette.background};
          --nixconf-panel: ${rgba glass.background settings.opacity};
          --nixconf-panel-border: ${rgba palette.border 0.22};
          --nixconf-panel-glow: 0 0 0 1px ${rgba palette.border 0.12}, 0 0 28px ${rgba palette.border 0.08},
            0 12px 40px ${rgba colors.base00 glass.shadowOpacity};
          --nixconf-accent: ${palette.accent};
          --nixconf-accent-alt: ${palette.accentAlt};
          --nixconf-text: ${palette.foregroundAlt};
          --nixconf-muted: ${colors.base04};
        }

        html,
        body {
          color: var(--nixconf-text) !important;
          background-color: var(--nixconf-bg) !important;
          background-image:
            radial-gradient(ellipse 80% 50% at 10% -10%, ${rgba palette.accentAlt 0.18}, transparent 55%),
            radial-gradient(ellipse 70% 45% at 100% 0%, ${rgba colors.base0E 0.14}, transparent 50%),
            radial-gradient(ellipse 60% 40% at 50% 110%, ${rgba palette.accent 0.12}, transparent 55%),
            linear-gradient(${rgba palette.border 0.03} 1px, transparent 1px),
            linear-gradient(90deg, ${rgba palette.border 0.03} 1px, transparent 1px),
            linear-gradient(180deg, ${palette.background} 0%, ${palette.backgroundAlt} 45%, ${palette.background} 100%) !important;
          background-size: auto, auto, auto, 48px 48px, 48px 48px, auto !important;
          background-attachment: fixed !important;
        }

        body::before {
          content: "";
          pointer-events: none;
          position: fixed;
          inset: 0;
          z-index: 0;
          background: repeating-linear-gradient(to bottom, transparent 0, transparent 2px, ${rgba colors.base00 0.08} 3px);
          opacity: 0.35;
        }

        #page_container,
        main,
        .services-container,
        .bookmark-container {
          position: relative;
          z-index: 1;
        }

        #information-widgets,
        .information-widget,
        .widget-container,
        [class*="information-widgets"] {
          backdrop-filter: blur(18px) saturate(140%);
          background: linear-gradient(135deg, ${rgba palette.accentAlt 0.08}, ${rgba colors.base0E 0.05} 50%, ${rgba glass.background 0.75}) !important;
          border: 1px solid var(--nixconf-panel-border) !important;
          box-shadow: var(--nixconf-panel-glow) !important;
          border-radius: 1rem !important;
        }

        .service-card,
        .bookmark,
        [class*="service-card"],
        [class*="bookmark-card"] {
          backdrop-filter: blur(16px) saturate(130%);
          background: var(--nixconf-panel) !important;
          border: 1px solid var(--nixconf-panel-border) !important;
          box-shadow: var(--nixconf-panel-glow) !important;
          border-radius: 0.9rem !important;
          transition: border-color 160ms ease, box-shadow 160ms ease, transform 160ms ease !important;
        }

        .service-card:hover,
        .bookmark:hover,
        [class*="service-card"]:hover,
        [class*="bookmark-card"]:hover {
          border-color: ${rgba palette.border 0.55} !important;
          box-shadow: 0 0 0 1px ${rgba palette.border 0.28}, 0 0 36px ${rgba palette.border 0.18}, 0 0 48px ${rgba colors.base0E 0.1} !important;
          transform: translateY(-1px);
        }

        h1,
        h2,
        .service-group-name,
        .bookmark-group-name,
        [class*="service-group"] button,
        [class*="bookmark-group"] button {
          color: var(--nixconf-accent-alt) !important;
          letter-spacing: 0.04em;
          text-shadow: 0 0 18px ${rgba palette.accentAlt 0.35};
          font-weight: 650 !important;
        }

        .service-title,
        .bookmark-text,
        a {
          color: var(--nixconf-text) !important;
        }

        .service-description,
        .service-card p,
        [class*="description"] {
          color: var(--nixconf-muted) !important;
          font-variant-numeric: tabular-nums;
        }

        .service-description {
          font-size: 0.86em !important;
        }

        input,
        select,
        textarea {
          background: ${rgba palette.background 0.85} !important;
          border: 1px solid ${rgba palette.border 0.25} !important;
          color: var(--nixconf-text) !important;
          border-radius: 0.75rem !important;
          box-shadow: inset 0 0 18px ${rgba palette.border 0.05};
        }

        input:focus {
          outline: none !important;
          border-color: ${colors.base0E} !important;
          box-shadow: 0 0 0 1px ${rgba colors.base0E 0.45}, 0 0 24px ${rgba colors.base0E 0.2} !important;
        }

        [class*="resource"],
        .gauge,
        .progressbar,
        progress {
          accent-color: var(--nixconf-accent-alt);
        }

        .status-dot,
        [class*="status"] {
          filter: drop-shadow(0 0 4px ${rgba palette.accentAlt 0.65});
        }

        ::-webkit-scrollbar {
          width: 10px;
          height: 10px;
        }
        ::-webkit-scrollbar-track {
          background: var(--nixconf-bg);
        }
        ::-webkit-scrollbar-thumb {
          background: linear-gradient(180deg, var(--nixconf-accent-alt), ${colors.base0E});
          border-radius: 999px;
          border: 2px solid var(--nixconf-bg);
        }

        footer,
        [class*="footer"] {
          color: var(--nixconf-muted) !important;
          opacity: 0.85;
        }
      '';
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

        portainerEnv = mkOption {
          type = types.int;
          default = 3;
          description = ''
            Portainer endpoint id used by the Homepage Portainer widget
            (from Portainer URL `#!/endpoints/<id>`). Local Docker endpoint
            is typically `1` on fresh installs; this fleet currently uses `3`.
            Source: https://gethomepage.dev/widgets/services/portainer/
          '';
        };
      };

      config = mkIf cfg.enable {
        services.homepage-dashboard = {
          enable = true;
          listenPort = cfg.port;
          allowedHosts = "*";
          environmentFiles = [ homepageEnvironmentFile ];
          customCSS = homepageCSS;

          settings = {
            title = "Nix Cyberpunk — ${hostName}";
            description = "Nix Cyberpunk Electric Dark — Application Theme";
            theme = "dark";
            color = "cyan";
            headerStyle = "boxedWidgets";
            statusStyle = "dot";
            cardBlur = "md";
            fullWidth = true;
            useEqualHeights = true;
            hideVersion = false;
            disableUpdateCheck = true;
            target = "_blank";
            quicklaunch = {
              searchDescriptions = true;
              provider = "duckduckgo";
            };
            # List form keeps group order (attrsets serialize alphabetically in YAML).
            # Source: https://gethomepage.dev/configs/settings/#sorting
            layout = [
              {
                "Local on this host" = {
                  style = "row";
                  columns = 4;
                  icon = "mdi-server-${c.cyan}";
                };
              }
              {
                "Public edge" = {
                  style = "row";
                  columns = 4;
                  icon = "mdi-earth-${c.magenta}";
                };
              }
              {
                "Fleet hosts" = {
                  style = "row";
                  columns = 4;
                  icon = "mdi-lan-${c.lime}";
                };
              }
              {
                "Developer references" = {
                  style = "row";
                  columns = 4;
                  icon = "si-nixos-${c.sky}";
                };
              }
            ];
          };

          # Split resource widgets into consistent labeled groups.
          # Source: https://gethomepage.dev/widgets/info/resources/
          widgets = [
            {
              resources = {
                label = "Compute";
                cpu = true;
                cputemp = true;
                memory = true;
                uptime = true;
                units = "metric";
                refresh = 3000;
                expanded = true;
              };
            }
            {
              resources = {
                label = "Storage";
                expanded = true;
                disk = [
                  "/"
                  "/persist"
                ];
              };
            }
            {
              resources = {
                label = "Network";
                network = true;
                refresh = 3000;
              };
            }
            {
              datetime = {
                text_size = "xl";
                locale = "en-GB";
                format = {
                  dateStyle = "medium";
                  timeStyle = "short";
                  hour12 = false;
                };
              };
            }
            {
              search = {
                provider = "duckduckgo";
                target = "_blank";
                showSearchSuggestions = true;
              };
            }
          ];

          services = [
            {
              "Local on this host" = localServiceCards;
            }
            {
              "Public edge" = publicServiceCards;
            }
            {
              "Developer references" = developerCards;
            }
          ];

          bookmarks = [
            {
              "Fleet hosts" = fleetBookmarks;
            }
          ];
        };

        networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

        # Homepage-local magic DNS stays host-scoped: enabled dashboard service names resolve
        # to loopback and proxy from port 80 to their original localhost-bound ports.
        # Include short "vpn" alias for bookmarks; nginx Host rewrite makes API work.
        networking.hosts."127.0.0.1" = unique (
          (builtins.attrNames localMagicDnsPorts) ++ optional (localMagicDnsPorts ? "vpn-proxy") "vpn"
        );

        services.nginx = mkIf (!traefikEnabled) {
          enable = true;
          # First alphabetical server_name becomes nginx's implicit default for unmatched Host
          # headers on 127.0.0.1:80. Without a catch-all, random public domains that hit loopback
          # (broken IPv6/Happy Eyeballs, bad hosts, browser HSTS edge cases) get served as ACP UI.
          # Source: https://nginx.org/en/docs/http/server_names.html#miscellaneous_names
          virtualHosts =
            (mapAttrs (name: service: {
              serverName = name;
              # Keep legacy http://vpn/ working after rename to vpn-proxy.
              serverAliases = optional (name == "vpn-proxy") "vpn";
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
                  # Prefer upstream Host (127.0.0.1:port). Short magic names like "vpn"
                  # make Elysia return NOT_FOUND for /api/*; X-Forwarded-Host keeps the
                  # browser-facing name for apps that care. Source: nginx $proxy_host.
                  proxy_set_header Host $proxy_host;
                  proxy_set_header X-Forwarded-Host $host;
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
            }) enabledLocalServices)
            // {
              "_" = {
                default = true;
                serverName = "_";
                listen = [
                  {
                    addr = "127.0.0.1";
                    port = 80;
                  }
                ];
                locations."/" = {
                  extraConfig = ''
                    default_type text/plain;
                    return 404 "unknown local magic-dns host\n";
                  '';
                };
              };
            };
        };

        services.traefik.dynamicConfigOptions.http = mkIf traefikEnabled {
          routers = mapAttrs' (
            name: _service:
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
