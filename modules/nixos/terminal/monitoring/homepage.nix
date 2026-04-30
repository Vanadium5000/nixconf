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
        mkEnableOption
        mkOption
        mkIf
        types
        ;
      cfg = config.services.homepage-monitor;
      publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;
      mkPublicUrl =
        subdomain: path:
        let
          host = if subdomain == null then publicBaseDomain else "${subdomain}.${publicBaseDomain}";
        in
        "https://${host}${path}";
    in
    {
      options.services.homepage-monitor = {
        enable = mkEnableOption "Homepage fleet dashboard portal";

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

          settings = {
            title = "NixOS Fleet";
            theme = "dark";
            color = "slate";

            # Allow access from Tailscale MagicDNS hostnames
            # Without this, Homepage rejects non-localhost connections
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
              "Monitoring" = [
                {
                  "Netdata — VPS" = {
                    icon = "netdata";
                    href = mkPublicUrl "netdata" "";
                    description = "Real-time system metrics (server host)";
                    widget = {
                      type = "netdata";
                      url = "http://127.0.0.1:19999";
                    };
                  };
                }
                {
                  "Mitmproxy — HTTPS Analyzer" = {
                    icon = "mdi-security";
                    href = mkPublicUrl "mitmproxy" "";
                    description = "HTTPS traffic analysis and debugging";
                  };
                }
              ];
            }
            {
              "Services" = [
                {
                  "CLIProxyAPI" = {
                    icon = "mdi-api";
                    href = mkPublicUrl "cliproxyapi" "/management.html";
                    description = "OpenAI-compatible API wrapping AI CLIs";
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
                    description = "SOCKS5/HTTP VPN proxy management";
                  };
                }
                {
                  "My Website" = {
                    icon = "mdi-web";
                    href = mkPublicUrl null "";
                    description = "Primary website";
                  };
                }
                {
                  "MongoDB Admin" = {
                    icon = "mdi-database";
                    href = mkPublicUrl "mongo" "";
                    description = "Mongo Express database management";
                  };
                }
              ];
            }
          ];

          bookmarks = [
            {
              "NixOS" = [
                {
                  "Package Search" = [
                    {
                      icon = "mdi-magnify";
                      href = "https://search.nixos.org/packages";
                    }
                  ];
                }
                {
                  "NixOS Options" = [
                    {
                      icon = "mdi-cog";
                      href = "https://search.nixos.org/options";
                    }
                  ];
                }
                {
                  "Nix Reference Manual" = [
                    {
                      icon = "mdi-book-open-variant";
                      href = "https://nix.dev/manual/nix/latest/";
                    }
                  ];
                }
              ];
            }
          ];
        };

        networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];

        # Next.js 15 requires strict Host header validation
        # Setting to * allows all hosts since it's already protected by Tailscale
        systemd.services.homepage-dashboard.environment = {
          HOMEPAGE_ALLOWED_HOSTS = lib.mkForce "*";
        };
      };
    };
}
