# VPN Proxy System

A modular proxy system that routes traffic through OpenVPN configurations with
network namespace isolation and zero IP leak guarantee.

## Architecture Overview

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Client Applications                            │
│                    (curl, browsers, any SOCKS5/HTTP client)                 │
└─────────────────────────────┬───────────────────────────┬───────────────────┘
                              │                           │
                              ▼                           ▼
                    ┌─────────────────┐         ┌─────────────────┐
                    │  SOCKS5 Proxy   │         │ HTTP CONNECT    │
                    │  localhost:10800│         │ localhost:10801 │
                    └────────┬────────┘         └────────┬────────┘
                             │                           │
                             └─────────────┬─────────────┘
                                           │
                              ┌────────────┴────────────┐
                              │    Username = VPN Slug  │
                              │    (or "random"/empty)  │
                              └────────────┬────────────┘
                                           │
              ┌────────────────────────────┼────────────────────────────┐
              ▼                            ▼                            ▼
    ┌─────────────────┐          ┌─────────────────┐          ┌─────────────────┐
    │  vpn-proxy-0    │          │  vpn-proxy-1    │          │  vpn-proxy-N    │
    │  ┌───────────┐  │          │  ┌───────────┐  │          │  ┌───────────┐  │
    │  │ OpenVPN   │  │          │  │ OpenVPN   │  │          │  │ OpenVPN   │  │
    │  │ + tun0    │  │          │  │ + tun0    │  │          │  │ + tun0    │  │
    │  └───────────┘  │          │  └───────────┘  │          │  └───────────┘  │
    │  ┌───────────┐  │          │  ┌───────────┐  │          │  ┌───────────┐  │
    │  │microsocks │  │          │  │microsocks │  │          │  │microsocks │  │
    │  │ :10900    │  │          │  │ :10901    │  │          │  │ :1090N    │  │
    │  └───────────┘  │          │  └───────────┘  │          │  └───────────┘  │
    │  ┌───────────┐  │          │  ┌───────────┐  │          │  ┌───────────┐  │
    │  │Kill-switch│  │          │  │Kill-switch│  │          │  │Kill-switch│  │
    │  │ (nftables)│  │          │  │ (nftables)│  │          │  │ (nftables)│  │
    │  └───────────┘  │          │  └───────────┘  │          │  └───────────┘  │
    └────────┬────────┘          └────────┬────────┘          └────────┬────────┘
             │                            │                            │
             └────────────────────────────┴────────────────────────────┘
                                          │
                                          ▼
                                     ┌─────────┐
                                     │ Internet│
                                     └─────────┘
```

## Protocols

### SOCKS5 Proxy (Port 10800)

Implements RFC 1928 (SOCKS Protocol Version 5) and RFC 1929 (Username/Password
Authentication).

**Supported Features:**

| Feature              | Status | Notes                        |
| -------------------- | ------ | ---------------------------- |
| CONNECT (0x01)       | ✅     | TCP connection tunneling     |
| BIND (0x02)          | ❌     | Not implemented              |
| UDP ASSOCIATE (0x03) | ❌     | Not implemented              |
| IPv4 addresses       | ✅     | Full support                 |
| Domain names         | ✅     | Resolved inside namespace    |
| IPv6 addresses       | ❌     | Would need IPv6 in namespace |
| No authentication    | ✅     | Uses random VPN              |
| Username/Password    | ✅     | Username = VPN slug          |

**Usage Examples:**

```bash
# Specific VPN (URL-encoded spaces)
curl --proxy "socks5://AirVPN%20AT%20Vienna@127.0.0.1:10800" https://api.ipify.org

# Random VPN (any of these work)
curl --proxy "socks5://random@127.0.0.1:10800" https://api.ipify.org
curl --proxy "socks5://127.0.0.1:10800" https://api.ipify.org

# With separate username flag
curl --proxy "socks5h://127.0.0.1:10800" --proxy-user "AirVPN AT Vienna:" https://api.ipify.org
```

### HTTP CONNECT Proxy (Port 10801)

Implements RFC 7231 §4.3.6 (HTTP CONNECT method) for HTTPS tunneling.

**Supported Features:**

| Feature              | Status | Notes                  |
| -------------------- | ------ | ---------------------- |
| CONNECT method       | ✅     | HTTPS tunneling        |
| Plain HTTP proxy     | ❌     | Only CONNECT supported |
| Basic authentication | ✅     | Username = VPN slug    |
| No authentication    | ✅     | Uses random VPN        |

**Usage Examples:**

```bash
# Specific VPN via --proxy-user
curl --proxy "http://127.0.0.1:10801" \
     --proxy-user "AirVPN AT Vienna:" \
     https://api.ipify.org

# Random VPN (no auth)
curl --proxy "http://127.0.0.1:10801" https://api.ipify.org

# URL-encoded username in proxy URL
curl -x "http://AirVPN%20AT%20Vienna@127.0.0.1:10801" https://api.ipify.org

# Environment variable
export https_proxy="http://127.0.0.1:10801"
curl https://api.ipify.org
```

## Authentication

Both proxies use authentication to select which VPN to route through:

| Authentication              | VPN Selection                     |
| --------------------------- | --------------------------------- |
| No auth / empty username    | Random VPN (rotates every 5 min)  |
| Username = "random"         | Random VPN (rotates every 5 min)  |
| Username = VPN display name | Specific VPN                      |
| Invalid username            | Notification + fallback to random |

**VPN Display Names:**

VPN names are derived from `.ovpn` filenames with formatting applied:

- `AirVPN_AT_Vienna.ovpn` → `AirVPN AT Vienna`
- `mullvad-us-nyc.ovpn` → `mullvad us nyc`

Use `vpn-resolver list` to see all available VPN names.

## Network Namespace Architecture

Each VPN runs in an isolated Linux network namespace with its own:

- Network stack (separate routing table, interfaces)
- DNS configuration (`/etc/netns/<name>/resolv.conf`)
- Firewall rules (nftables kill-switch)

### Addressing Scheme

```text
Namespace: vpn-proxy-{index}
Host veth: veth-h-{index}  →  10.200.{index}.1/24
NS veth:   veth-n-{index}  →  10.200.{index}.2/24
SOCKS port inside NS:         10900 + {index}
```

### Kill-Switch Implementation

The nftables kill-switch ensures zero IP leaks:

```text
table inet vpn_killswitch {
    chain output {
        type filter hook output priority 0; policy drop;

        # Allow loopback
        oifname "lo" accept

        # Allow VPN tunnel only
        oifname "tun*" accept

        # Allow VPN handshake (before tun0 exists)
        ip daddr <vpn_server_ip> udp dport <vpn_port> accept
        ip daddr <vpn_server_ip> tcp dport <vpn_port> accept

        # Allow responses back to host veth
        oifname "veth-n-*" accept

        # Allow ICMP for diagnostics
        ip protocol icmp accept

        # Everything else: DROP (implicit)
    }
}
```

**Security Guarantee:** If the VPN tunnel drops, all traffic is blocked. There
is no fallback to the host's real IP address.

### DNS Isolation

Each namespace has its own `/etc/netns/<name>/resolv.conf`:

```text
nameserver 1.1.1.1
nameserver 1.0.0.1
```

This prevents DNS queries from leaking through the host's resolver.

## State Management

All runtime state is stored in tmpfs at `/dev/shm/vpn-proxy-$UID/`:

| File                         | Purpose                                |
| ---------------------------- | -------------------------------------- |
| `state.json`                 | Namespace tracking, random VPN state   |
| `resolver-cache.json`        | VPN config cache with mtime validation |
| `openvpn-vpn-proxy-N.pid`    | OpenVPN daemon PID                     |
| `openvpn-vpn-proxy-N.log`    | OpenVPN logs                           |
| `ns-vpn-proxy-N.json`        | Namespace metadata                     |
| `microsocks-vpn-proxy-N.pid` | microsocks PID                         |

**State is ephemeral:** Reboots clear `/dev/shm`, and the proxy cleans up stale
state on startup anyway.

## CLI Commands

### vpn-proxy (SOCKS5)

```bash
vpn-proxy serve         # Start SOCKS5 server (default)
vpn-proxy status        # Show active VPNs and idle times
vpn-proxy stop-all      # Destroy all namespaces
vpn-proxy rotate-random # Force random VPN rotation
vpn-proxy --help        # Show help
```

### http-proxy (HTTP CONNECT)

```bash
http-proxy serve         # Start HTTP CONNECT server (default)
http-proxy status        # Show active VPNs (same as vpn-proxy)
http-proxy stop-all      # Destroy all namespaces
http-proxy rotate-random # Force random VPN rotation
http-proxy --help        # Show help
```

### vpn-resolver

```bash
vpn-resolver list              # List all VPNs (human readable)
vpn-resolver list-json         # List all VPNs (JSON)
vpn-resolver resolve <slug>    # Resolve slug to VPN config
vpn-resolver random            # Get a random VPN config
vpn-resolver server-ip <path>  # Get server IP from .ovpn file
```

### vpn-proxy-netns (Low-level)

```bash
vpn-proxy-netns create <name> <index> <vpn_ip> [port]
vpn-proxy-netns destroy <name>
vpn-proxy-netns list
vpn-proxy-netns check <name>
vpn-proxy-netns cleanup-all
```

## Configuration

### Environment Variables

| Variable                     | Default         | Description                           |
| ---------------------------- | --------------- | ------------------------------------- |
| `VPN_DIR`                    | `~/Shared/VPNs` | Directory containing `.ovpn` files    |
| `VPN_PROXY_PORT`             | `10800`         | SOCKS5 proxy port                     |
| `VPN_HTTP_PROXY_PORT`        | `10801`         | HTTP CONNECT proxy port               |
| `VPN_PROXY_IDLE_TIMEOUT`     | `300`           | Seconds before idle namespace cleanup |
| `VPN_PROXY_RANDOM_ROTATION`  | `300`           | Seconds between random VPN rotation   |
| `VPN_PROXY_NOTIFY_ROTATION`  | `0`             | Show notification on rotation (0/1)   |
| `VPN_PROXY_CLEANUP_INTERVAL` | `60`            | Cleanup daemon check interval         |
| `VPN_PROXY_NETNS_SCRIPT`     | (auto)          | Path to netns.sh script               |

### NixOS Service Options

```nix
services.vpn-proxy = {
  enable = true;              # Enable the proxy services
  port = 10800;               # SOCKS5 port
  httpPort = 10801;           # HTTP CONNECT port
  vpnDir = "/path/to/vpns";   # .ovpn file directory
  idleTimeout = 300;          # Namespace idle timeout
  randomRotation = 300;       # Random VPN rotation interval
};
```

## Systemd Services

When enabled via NixOS, three services are created:

| Service                     | Description               |
| --------------------------- | ------------------------- |
| `vpn-proxy.service`         | SOCKS5 proxy server       |
| `http-proxy.service`        | HTTP CONNECT proxy server |
| `vpn-proxy-cleanup.service` | Idle cleanup daemon       |

```bash
# Check status
systemctl status vpn-proxy http-proxy vpn-proxy-cleanup

# View logs
journalctl -u vpn-proxy -f
journalctl -u http-proxy -f

# Restart after config changes
systemctl restart vpn-proxy http-proxy
```

## Integration Examples

### Browser Configuration

**Firefox:**

1. Settings → Network Settings → Manual proxy configuration
2. SOCKS Host: `127.0.0.1`, Port: `10800`, SOCKS v5
3. Check "Proxy DNS when using SOCKS v5"

**Chromium:**

```bash
chromium --proxy-server="socks5://127.0.0.1:10800"
```

### Application-Specific Proxy

```bash
# git over SOCKS5
git config --global http.proxy "socks5://127.0.0.1:10800"

# npm
npm config set proxy "http://127.0.0.1:10801"

# Environment variables
export http_proxy="http://127.0.0.1:10801"
export https_proxy="http://127.0.0.1:10801"
export ALL_PROXY="socks5://127.0.0.1:10800"
```

### qs-vpn Integration

The `qs-vpn` script supports copying proxy URLs to clipboard:

- **Enter**: Connect via NetworkManager (existing behavior)
- **k**: Copy SOCKS5 proxy URL to clipboard

```text
socks5://AirVPN%20AT%20Vienna@127.0.0.1:10800
```

The VPN activates automatically when the proxy link is first used.

## Troubleshooting

### Common Issues

#### Namespace creation failed

- Check sudo permissions: `sudo -v`
- Verify directories exist: `ls -la /run/netns /etc/netns`
- Check for stale namespaces: `vpn-proxy-netns cleanup-all`

#### VPN tunnel failed to establish

- Check OpenVPN logs: `cat /dev/shm/vpn-proxy-*/openvpn-*.log`
- Verify `.ovpn` file is valid: `sudo openvpn --config /path/to/vpn.ovpn`
- Check VPN server is reachable: `ping <vpn_server_ip>`

#### Connection refused on proxy port

- Verify service is running: `systemctl status vpn-proxy`
- Check port is listening: `ss -tlnp | grep 10800`
- Try restarting: `systemctl restart vpn-proxy`

#### DNS leaks

- Ensure "Proxy DNS" is enabled in browser
- Use `socks5h://` (not `socks5://`) for DNS-over-proxy
- Check namespace DNS: `cat /etc/netns/vpn-proxy-0/resolv.conf`

### Debug Commands

```bash
# List active namespaces
sudo ip netns list | grep vpn-proxy

# Check namespace connectivity
sudo ip netns exec vpn-proxy-0 curl https://api.ipify.org

# View namespace interfaces
sudo ip netns exec vpn-proxy-0 ip addr

# Check kill-switch rules
sudo ip netns exec vpn-proxy-0 nft list ruleset

# View state
cat /dev/shm/vpn-proxy-$(id -u)/state.json | jq .
```

## File Structure

```text
modules/nixos/scripts/bunjs/proxy/
├── PROXY.md           # This documentation
├── shared.ts          # Common utilities (state, logging, namespace mgmt)
├── vpn-resolver.ts    # VPN config parsing and caching
├── socks5-proxy.ts    # SOCKS5 proxy server
├── http-proxy.ts      # HTTP CONNECT proxy server
├── cleanup.ts         # Idle cleanup daemon
├── netns.sh           # Network namespace setup script
└── service.nix        # NixOS systemd service definitions
```

## Security Considerations

1. **Kill-switch is mandatory**: All traffic is blocked if VPN drops
2. **DNS isolation**: Each namespace has its own resolvers
3. **No credential storage**: VPN configs are read-only from disk
4. **tmpfs state**: Sensitive data never persists to disk
5. **Namespace isolation**: VPNs cannot interfere with each other
6. **localhost-only**: Proxies only listen on `127.0.0.1`

## Performance Notes

- **Namespace creation**: ~3-5 seconds (OpenVPN handshake)
- **First request**: May be slow while namespace is created
- **Subsequent requests**: Fast (reuses existing namespace)
- **Idle cleanup**: 5 minutes default (configurable)
- **Random rotation**: 5 minutes default (configurable)
- **Memory per namespace**: ~10-20MB (OpenVPN + microsocks)
