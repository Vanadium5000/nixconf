# =========================================================================
# mitmproxy — on-demand HTTPS traffic analysis service
# =========================================================================
#
# == How mitmproxy intercepts HTTPS traffic ==
#
# HTTPS encryption normally prevents inspecting request/response data.
# mitmproxy breaks this open by performing a "man-in-the-middle" attack
# on your OWN machine, for security analysis and debugging.
#
# The interception flow:
#
#   1. CERTIFICATE AUTHORITY
#      The module uses a pre-generated root CA stored in the nixconf repo
#      (monitoring/mitmproxy-ca/). This CA is installed into the system
#      trust store, allowing mitmproxy to forge certificates seamlessly.
#
#   2. CLIENT CONNECTS
#      An app (curl, browser, etc.) tries to connect to https://example.com.
#      Through proxy settings or network-level redirection, the connection
#      is routed to mitmproxy instead of directly to the server.
#
#   3. CERTIFICATE FORGING
#      mitmproxy reads the TLS ClientHello to learn the target hostname.
#      It dynamically generates a FAKE certificate for "example.com",
#      signed by its own CA. This happens in milliseconds, per-connection.
#
#   4. DUAL TLS TUNNELS
#      Two separate TLS sessions exist simultaneously:
#        [App ←TLS→ mitmproxy]  and  [mitmproxy ←TLS→ example.com]
#      The app thinks it's talking to example.com (because it trusts the
#      mitmproxy CA). The real server has no idea a proxy exists.
#
#   5. PLAINTEXT VISIBILITY
#      Between the two TLS tunnels, mitmproxy sees all HTTP traffic in
#      plaintext — URLs, headers, cookies, request bodies, response data.
#      This is logged in the mitmweb UI (Chrome DevTools-like interface).
#
# == Modes of operation ==
#
#   "explicit" (default, safest):
#     Set HTTPS_PROXY=http://127.0.0.1:8080 per-app.
#     Only proxy-aware apps route through mitmproxy.
#     Best for targeted debugging of specific applications.
#
#   "transparent" (system-wide):
#     nftables OUTPUT chain rules redirect ALL port 80/443 traffic.
#     Uses a dedicated nftables table (inet mitmproxy) isolated from
#     the NixOS firewall. The mitmproxy user's traffic is excluded
#     to prevent infinite routing loops.
#     ⚠ Captures EVERYTHING — including package managers, daemons, etc.
#
#   "local" (eBPF, EXPERIMENTAL):
#     Uses eBPF to hook into connect() syscall at cgroup level.
#     Can target specific binary names (interceptApps option).
#     ⚠ WARNING: On Linux, this mode is experimental as of mitmproxy 11.x
#     ⚠ Known issues: DNS redirection loop can break all connectivity,
#     ⚠ process name filtering is unreliable for most binaries.
#     ⚠ See: https://github.com/mitmproxy/mitmproxy/issues/7787
#     ⚠ Prefer "explicit" mode for reliable per-app interception.
#
# == Quick start ==
#
#   systemctl start mitmproxy              # start on-demand
#   open http://127.0.0.1:8083             # mitmweb UI (password: nixos)
#   HTTPS_PROXY=http://127.0.0.1:8080 curl https://api.example.com
#   systemctl stop mitmproxy               # stop when done
#
# == Security ==
#
#   Only intercept YOUR OWN traffic for analysis. mitmproxy logs expose
#   plaintext passwords, session cookies, and API keys. Never expose the
#   mitmweb port (8083) to the internet. The service binds to 127.0.0.1.
#
# =========================================================================
{ self, ... }:
{
  flake.nixosModules.mitmproxy =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkPackageOption
        mkOption
        mkIf
        mkMerge
        types
        concatStringsSep
        splitString
        hasPrefix
        hasInfix
        ;
      cfg = config.services.mitmproxy;

      # Build the --mode flag(s) based on configuration
      modeFlags =
        if cfg.mode == "explicit" then
          "--mode regular"
        else if cfg.mode == "transparent" then
          "--mode transparent"
        else if cfg.mode == "local" && cfg.interceptApps != [ ] then
          # Multiple --mode flags for per-app eBPF interception
          concatStringsSep " " (map (app: "--mode local:${app}") cfg.interceptApps)
        else
          "--mode local";

      # nftables script to redirect traffic through the transparent proxy
      # Uses a dedicated table so it doesn't conflict with NixOS firewall (nixos-fw)
      nftablesRedirectScript = pkgs.writeShellScript "mitmproxy-nft-redirect" ''
        # Create dedicated table for mitmproxy transparent mode
        # Isolated from NixOS firewall tables — safe to add/remove dynamically
        ${pkgs.nftables}/bin/nft add table inet mitmproxy
        ${pkgs.nftables}/bin/nft add chain inet mitmproxy output '{ type nat hook output priority -100; }'

        # Get the UID of the mitmproxy user to exclude its own traffic
        # Without this exclusion, mitmproxy's outbound connections loop back to itself
        MITMPROXY_UID=$(${pkgs.coreutils}/bin/id -u mitmproxy)

        # Redirect HTTP/HTTPS to the proxy, excluding mitmproxy's own traffic
        ${pkgs.nftables}/bin/nft add rule inet mitmproxy output \
          meta skuid != "$MITMPROXY_UID" tcp dport 80 redirect to :${toString cfg.proxyPort}
        ${pkgs.nftables}/bin/nft add rule inet mitmproxy output \
          meta skuid != "$MITMPROXY_UID" tcp dport 443 redirect to :${toString cfg.proxyPort}
      '';

      # Cleanup script — drops the entire mitmproxy table
      # Critical: without this, stopping the service blackholes all HTTP traffic
      nftablesCleanupScript = pkgs.writeShellScript "mitmproxy-nft-cleanup" ''
        ${pkgs.nftables}/bin/nft delete table inet mitmproxy 2>/dev/null || true
      '';

      pemBlocks =
        secret:
        let
          lines = splitString "\n" secret;
          step =
            state: line:
            let
              beginLine = hasPrefix "-----BEGIN " line;
              endLine = hasPrefix "-----END " line;
              nextCurrent =
                if beginLine then
                  [ line ]
                else if state.capturing then
                  state.current ++ [ line ]
                else
                  [ ];
              completedBlock =
                if state.capturing && endLine then
                  [ (concatStringsSep "\n" nextCurrent) ]
                else
                  [ ];
            in
            {
              capturing = beginLine || (state.capturing && !endLine);
              current = if endLine then [ ] else nextCurrent;
              blocks = state.blocks ++ completedBlock;
            };
          result = builtins.foldl' step {
            capturing = false;
            current = [ ];
            blocks = [ ];
          } lines;
        in
        result.blocks;

      firstPemBlockContaining = marker: secret:
        let
          matches = builtins.filter (block: hasInfix marker block) (pemBlocks secret);
        in
        if matches == [ ] then
          ""
        else
          builtins.head matches;

      mitmproxyCaKeyPem = firstPemBlockContaining "BEGIN RSA PRIVATE KEY" (self.secrets.MITMPROXY_CA_KEY or "");
      mitmproxyCaCertPem = firstPemBlockContaining "BEGIN CERTIFICATE" (self.secrets.MITMPROXY_CA_CERT or "");

      # Some password-store exports accidentally concatenate key+cert PEMs into one secret.
      # Extracting only the expected block keeps the trusted cert and private key paths unambiguous.
      caKeyFile = pkgs.writeText "mitmproxy-ca.pem" mitmproxyCaKeyPem;
      caCertFile = pkgs.writeText "mitmproxy-ca-cert.pem" mitmproxyCaCertPem;

      deployCAScript = pkgs.writeShellScript "mitmproxy-deploy-ca" ''
        # Ensure the data directory exists
        mkdir -p "${cfg.dataDir}"

        # Copy only the expected PEM blocks so malformed concatenated secrets cannot widen trust.
        cp -f ${caKeyFile} "${cfg.dataDir}/mitmproxy-ca.pem"
        cp -f ${caCertFile} "${cfg.dataDir}/mitmproxy-ca-cert.pem"

        # Ensure correct ownership and permissions
        chown -R mitmproxy:mitmproxy "${cfg.dataDir}"
        chmod -R 600 "${cfg.dataDir}"/*
        chmod 700 "${cfg.dataDir}"
      '';
    in
    {
      options.services.mitmproxy = {
        enable = mkEnableOption "mitmproxy HTTPS traffic analyzer";

        package = mkPackageOption pkgs "mitmproxy" { };

        mode = mkOption {
          type = types.enum [
            "explicit"
            "transparent"
            "local"
          ];
          default = "explicit";
          description = ''
            Interception mode:
            - "explicit": apps must set HTTPS_PROXY env var (safest, most targeted)
            - "transparent": nftables redirects all port 80/443 traffic (system-wide)
            - "local": eBPF hooks connect() syscall (EXPERIMENTAL on Linux — may break DNS)
          '';
        };

        webPort = mkOption {
          type = types.port;
          default = 8083;
          description = ''
            Port for the mitmweb browser UI.
            Avoids 8081 (used by mongo-express on ionos_vps).
          '';
        };

        proxyPort = mkOption {
          type = types.port;
          default = 8080;
          description = "Port the proxy listens on (for explicit and transparent modes).";
        };

        dataDir = mkOption {
          type = types.path;
          default = "/var/lib/mitmproxy";
          description = ''
            Directory for mitmproxy's CA certificates and configuration.
          '';
        };

        trustCA = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Trust the repository's mitmproxy CA certificate system-wide via security.pki.

            Because the CA certificate is pre-generated and stored in the repository
            (modules/nixos/terminal/monitoring/mitmproxy-ca/), you can safely enable
            this on the very first deploy without needing to start the service first.

            Without this, apps will show certificate errors when proxied.
            Only the "explicit" mode works without CA trust (apps that
            support HTTPS_PROXY can be configured to skip cert verification).
          '';
        };

        interceptApps = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            For "local" mode only: specific binary names to intercept.
            Empty list = intercept everything.
            Example: [ "curl" "wget" "python3" ]

            Note: process name filtering is unreliable in mitmproxy's
            eBPF implementation as of v11.x — some binaries may not be
            captured correctly.
          '';
        };
      };

      config = mkIf cfg.enable {
        # Make mitmproxy CLI tools available (mitmproxy, mitmweb, mitmdump)
        environment.systemPackages = [ cfg.package ];

        # Dedicated user for the service — also used by transparent mode's
        # nftables UID-based exclusion to prevent routing loops
        users.users.mitmproxy = {
          isSystemUser = true;
          group = "mitmproxy";
          home = cfg.dataDir;
          createHome = true;
        };
        users.groups.mitmproxy = { };

        systemd.services.mitmproxy = {
          description = "mitmproxy HTTPS Traffic Analyzer";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          # NOT in wantedBy — this is an on-demand service
          # Start with: systemctl start mitmproxy
          # Stop with:  systemctl stop mitmproxy

          serviceConfig = mkMerge [
            # Common config for all modes
            {
              # Deploy the pre-generated CA certificates before starting
              ExecStartPre = [ "+${deployCAScript}" ];

              ExecStart = concatStringsSep " " [
                "${cfg.package}/bin/mitmweb"
                modeFlags
                "--web-host 127.0.0.1"
                "--web-port ${toString cfg.webPort}"
                "--set confdir=${cfg.dataDir}"
                "--no-web-open-browser" # Don't try to open browser on headless server
                "--set web_password=nixos" # Fixed password for the web UI
                # Listen host/port only applies to explicit and transparent modes
                (
                  if cfg.mode != "local" then
                    "--listen-host 127.0.0.1 --listen-port ${toString cfg.proxyPort}"
                  else
                    ""
                )
              ];

              User = "mitmproxy";
              Group = "mitmproxy";
              Restart = "on-failure";
              RestartSec = "5s";

              # Sandboxing
              ProtectHome = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ReadWritePaths = [ cfg.dataDir ];
              PrivateDevices = true;
            }

            # Explicit mode — most restrictive sandboxing
            (mkIf (cfg.mode == "explicit") {
              NoNewPrivileges = true;
            })

            # Transparent mode — needs network manipulation capabilities
            (mkIf (cfg.mode == "transparent") {
              NoNewPrivileges = false; # capabilities require privilege escalation
              AmbientCapabilities = [
                "CAP_NET_ADMIN"
                "CAP_NET_RAW"
              ];
              CapabilityBoundingSet = [
                "CAP_NET_ADMIN"
                "CAP_NET_RAW"
              ];

              # Set up and tear down nftables rules for traffic redirection
              ExecStartPre = [
                "+${nftablesRedirectScript}"
              ];
              ExecStopPost = [
                "+${nftablesCleanupScript}"
              ];
            })

            # Local/eBPF mode — needs kernel-level capabilities for BPF programs
            (mkIf (cfg.mode == "local") {
              NoNewPrivileges = false; # eBPF loading requires privilege escalation
              AmbientCapabilities = [
                "CAP_BPF"
                "CAP_SYS_ADMIN"
                "CAP_NET_ADMIN"
                "CAP_SYS_RESOURCE"
              ];
              CapabilityBoundingSet = [
                "CAP_BPF"
                "CAP_SYS_ADMIN"
                "CAP_NET_ADMIN"
                "CAP_SYS_RESOURCE"
              ];
              LimitMEMLOCK = "infinity"; # eBPF maps require locked memory
            })
          ];
        };

        # Trust the pre-generated mitmproxy CA system-wide so intercepted
        # HTTPS works without certificate errors in all applications.
        security.pki.certificates = mkIf cfg.trustCA [
          mitmproxyCaCertPem
        ]; # Trust only the certificate PEM so a pasted private key can never land in the system trust store.
      };
    };
}
