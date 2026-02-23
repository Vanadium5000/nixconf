# VPN Proxy System

A modular proxy system that routes traffic through OpenVPN configurations with
network namespace isolation and zero IP leak guarantee. Also supports a "none"
mode for direct connections that bypass device-level VPNs.

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
                              │ "random"/empty/"none"   │
                              └────────────┬────────────┘
                                           │
          ┌────────────────────────────────┼──────────────────┐
          ▼                                ▼                  ▼
┌─────────────────┐              ┌─────────────────┐  ┌─────────────────┐
│  vpn-proxy-0    │              │  vpn-proxy-1    │  │  vpn-proxy-N    │
│  ┌───────────┐  │              │  ┌───────────┐  │  │  ┌───────────┐  │
│  │ OpenVPN   │  │              │  │ (no VPN)  │  │  │  │ OpenVPN   │  │
│  │ + tun0    │  │              │  │  direct   │  │  │  │ + tun0    │  │
│  └───────────┘  │              │  └───────────┘  │  │  └───────────┘  │
│  ┌───────────┐  │              │  ┌───────────┐  │  │  ┌───────────┐  │
│  │microsocks │  │              │  │microsocks │  │  │  │microsocks │  │
│  │ :10900    │  │              │  │ :10901    │  │  │  │ :1090N    │  │
│  └───────────┘  │              │  └───────────┘  │  │  └───────────┘  │
│  ┌───────────┐  │              │                 │  │  ┌───────────┐  │
│  │Kill-switch│  │              │  (no kill-sw)   │  │  │Kill-switch│  │
│  │ (nftables)│  │              │                 │  │  │ (nftables)│  │
│  └───────────┘  │              │                 │  │  └───────────┘  │
└────────┬────────┘              └────────┬────────┘  └────────┬────────┘
         │                                │                    │
         └────────────────────────────────┴────────────────────┘
                                          │
                                          ▼
                                     ┌─────────┐
                                     │ Internet│
                                     └─────────┘
```

## Protocols

Both proxies share the same namespace pool and authentication mechanism. Use
whichever protocol your application supports.

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
# Specific VPN (use slug from `vpn-resolver list` - no spaces needed)
curl --proxy "socks5h://AirVPNATViennaAlderaminUDP80Entry3@127.0.0.1:10800" https://api.ipify.org

# Random VPN (any of these work)
curl --proxy "socks5h://random@127.0.0.1:10800" https://api.ipify.org
curl --proxy "socks5h://127.0.0.1:10800" https://api.ipify.org

# Direct connection (bypass device VPN, use real IP)
curl --proxy "socks5h://none@127.0.0.1:10800" https://api.ipify.org

# With separate --proxy-user flag
curl --proxy "socks5h://127.0.0.1:10800" --proxy-user "AirVPNATViennaAlderaminUDP80Entry3:" https://api.ipify.org

# Using -x shorthand
curl -x "socks5h://AirVPNATViennaAlderaminUDP80Entry3@127.0.0.1:10800" https://api.ipify.org

# Environment variable
export ALL_PROXY="socks5h://127.0.0.1:10800"
curl https://api.ipify.org
```

> **Note:** Use `socks5h://` (with `h`) to resolve DNS through the proxy. With
> plain `socks5://`, DNS is resolved locally which may leak your real IP via
> DNS queries.

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
# Specific VPN via --proxy-user (use slug from `vpn-resolver list`)
curl --proxy "http://127.0.0.1:10801" --proxy-user "AirVPNATViennaAlderaminUDP80Entry3:" https://api.ipify.org

# Random VPN (no auth)
curl --proxy "http://127.0.0.1:10801" https://api.ipify.org

# Direct connection (bypass device VPN, use real IP)
curl --proxy "http://127.0.0.1:10801" --proxy-user "none:" https://api.ipify.org

# Username in proxy URL
curl --proxy "http://AirVPNATViennaAlderaminUDP80Entry3@127.0.0.1:10801" https://api.ipify.org

# Using -x shorthand
curl -x "http://AirVPNATViennaAlderaminUDP80Entry3@127.0.0.1:10801" https://api.ipify.org

# Environment variables (used by most CLI tools: curl, wget, pip, npm, etc.)
export http_proxy="http://127.0.0.1:10801"
export https_proxy="http://127.0.0.1:10801"
curl https://api.ipify.org
```

> **Note:** The HTTP proxy only supports the CONNECT method for HTTPS
> tunneling. Plain HTTP requests will receive a 405 Method Not Allowed error.

## Authentication

Both proxies use authentication to select which VPN to route through:

| Authentication              | VPN Selection                                   |
| --------------------------- | ----------------------------------------------- |
| No auth / empty username    | Random VPN (rotates every 5 min)                |
| Username = "random"         | Random VPN (rotates every 5 min)                |
| Username = "none"           | Direct connection (no VPN, bypasses device VPN) |
| Username = VPN display name | Specific VPN                                    |
| Invalid username            | Notification + fallback to random               |

**VPN Slugs:**

VPN slugs are derived from `.ovpn` filenames with spaces removed for easier usage:

- `AirVPN_AT_Vienna.ovpn` → slug: `AirVPNATVienna`, display: `AirVPN AT Vienna`
- `mullvad-us-nyc.ovpn` → slug: `mullvadusnyc`, display: `mullvad us nyc`

Spaces in input are ignored, so `AirVPN AT Vienna` and `AirVPNATVienna` both work.

Use `vpn-resolver list` to see all available VPN slugs.

## Direct Connection Mode ("none")

When the username is set to `"none"`, the proxy creates a network namespace
with **no VPN and no kill-switch**. Traffic goes directly through the host's
real internet connection via NAT masquerading.

**Why?** A network namespace has its own routing table, completely independent
of the host. If the host has an active VPN (e.g., via NetworkManager OpenVPN),
the "none" namespace bypasses it — traffic exits through the host's physical
interface, not through the VPN tunnel.

**Use cases:**

- Accessing services that block VPN IP addresses
- Checking your real IP while a device VPN is active
- Running specific requests without VPN overhead

**How it works:**

1. A new namespace is created with a veth pair and NAT (same as VPN namespaces)
2. No OpenVPN is started — no tunnel, no kill-switch
3. microsocks runs inside the namespace for SOCKS5 proxying
4. Traffic routes: app → proxy → namespace → host NAT → real internet

**The namespace is idle-cleaned** like VPN namespaces (default 5 minutes).

```bash
# SOCKS5
curl --proxy "socks5h://none@127.0.0.1:10800" https://api.ipify.org

# HTTP CONNECT
curl --proxy "http://127.0.0.1:10801" --proxy-user "none:" https://api.ipify.org
```

## Network Namespace Architecture

Each VPN runs in an isolated Linux network namespace with its own:

- Network stack (separate routing table, interfaces)
- DNS configuration (`/etc/netns/<name>/resolv.conf`)
- Firewall rules (nftables kill-switch)

### Addressing Scheme

```text
Namespace: vpn-proxy-{index}
Host veth: veth-h-{index}  →  10.200.{subnet}.1/24 (subnet = index % 254 + 1)
NS veth:   veth-n-{index}  →  10.200.{subnet}.2/24
SOCKS port inside NS:         10900 + {index % 50000}
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
vpn-proxy-netns create-direct <name> <index>
vpn-proxy-netns destroy <name>
vpn-proxy-netns list
vpn-proxy-netns check <name>
vpn-proxy-netns cleanup-all
```

## Configuration

### Environment Variables

| Variable                     | Default         | Description                                   |
| ---------------------------- | --------------- | --------------------------------------------- |
| `VPN_DIR`                    | `~/Shared/VPNs` | Directory containing `.ovpn` files            |
| `VPN_PROXY_PORT`             | `10800`         | SOCKS5 proxy port                             |
| `VPN_HTTP_PROXY_PORT`        | `10801`         | HTTP CONNECT proxy port                       |
| `VPN_PROXY_BIND_ADDRESS`     | `0.0.0.0`       | Bind address (`127.0.0.1` for localhost only) |
| `VPN_PROXY_IDLE_TIMEOUT`     | `300`           | Seconds before idle namespace cleanup         |
| `VPN_PROXY_RANDOM_ROTATION`  | `300`           | Seconds between random VPN rotation           |
| `VPN_PROXY_NOTIFY_ROTATION`  | `0`             | Show notification on rotation (0/1)           |
| `VPN_PROXY_CLEANUP_INTERVAL` | `60`            | Cleanup daemon check interval                 |
| `VPN_PROXY_NETNS_SCRIPT`     | (auto)          | Path to netns.sh script                       |

### NixOS Service Options

```nix
services.vpn-proxy = {
  enable = true;              # Enable the proxy services
  port = 10800;               # SOCKS5 port
  httpPort = 10801;           # HTTP CONNECT port
  bindAddress = "0.0.0.0";    # Default; use "127.0.0.1" for localhost only
  vpnDir = "/path/to/vpns";   # .ovpn file directory
  idleTimeout = 300;          # Namespace idle timeout
  randomRotation = 300;       # Random VPN rotation interval
};

# Open firewall ports for LAN access
networking.firewall.allowedTCPPorts = [ 10800 10801 ];
```

Configure LAN clients to use `<your-server-ip>:10800` (SOCKS5) or
`<your-server-ip>:10801` (HTTP).

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

**Firefox (SOCKS5):**

1. Settings → Network Settings → Manual proxy configuration
2. SOCKS Host: `127.0.0.1`, Port: `10800`, SOCKS v5
3. Check "Proxy DNS when using SOCKS v5"

**Firefox (HTTP):**

1. Settings → Network Settings → Manual proxy configuration
2. HTTP Proxy: `127.0.0.1`, Port: `10801`
3. Also use this proxy for HTTPS: ✓

**Chromium (SOCKS5):**

```bash
chromium --proxy-server="socks5://127.0.0.1:10800"
```

**Chromium (HTTP):**

```bash
chromium --proxy-server="http://127.0.0.1:10801"
```

### Application-Specific Proxy

```bash
# git (SOCKS5)
git config --global http.proxy "socks5h://127.0.0.1:10800"

# git (HTTP)
git config --global http.proxy "http://127.0.0.1:10801"

# npm (HTTP only)
npm config set proxy "http://127.0.0.1:10801"
npm config set https-proxy "http://127.0.0.1:10801"

# pip (HTTP)
pip install --proxy "http://127.0.0.1:10801" package-name

# wget (HTTP)
wget -e use_proxy=yes -e http_proxy=http://127.0.0.1:10801 https://example.com
```

### Proxy Environment Variables

```bash
# HTTP proxy (works with most CLI tools: curl, wget, pip, npm, etc.)
export http_proxy="http://127.0.0.1:10801"
export https_proxy="http://127.0.0.1:10801"

# SOCKS5 proxy (works with curl, git, and SOCKS-aware tools)
export ALL_PROXY="socks5h://127.0.0.1:10800"

# With specific VPN (URL-encoded spaces - use FULL name from `vpn-resolver list`)
export ALL_PROXY="socks5h://AirVPN%20AT%20Vienna%20Alderamin%20UDP%2080%20Entry3@127.0.0.1:10800"
export https_proxy="http://AirVPN%20AT%20Vienna%20Alderamin%20UDP%2080%20Entry3:@127.0.0.1:10801"
```

### SSH via Proxy

```bash
# SOCKS5 (requires netcat-openbsd)
ssh -o ProxyCommand="nc -X 5 -x 127.0.0.1:10800 %h %p" user@host

# HTTP CONNECT (requires corkscrew or connect-proxy)
ssh -o ProxyCommand="corkscrew 127.0.0.1 10801 %h %p" user@host
```

### qs-vpn Integration

The `qs-vpn` script supports copying proxy URLs to clipboard:

- **Enter**: Connect via NetworkManager (existing behavior)
- **k**: Copy SOCKS5 proxy URL to clipboard

```text
socks5://AirVPN%20AT%20Vienna%20Alderamin%20UDP%2080%20Entry3@127.0.0.1:10800
```

The VPN activates automatically when the proxy link is first used.

## Programmatic Usage

### Bun / TypeScript

Bun's `fetch` doesn't reliably parse URL-encoded credentials from proxy URLs.
Use the object format with an explicit `Proxy-Authorization` header:

```typescript
// ❌ UNRELIABLE - Bun may fail to parse URL-encoded username
await fetch("https://api.ipify.org", {
  proxy:
    "http://AirVPN%20AT%20Vienna%20Alderamin%20UDP%2080%20Entry3:@127.0.0.1:10801",
});

// ✅ CORRECT - Use object format with explicit header
const vpnName = "AirVPN AT Vienna Alderamin UDP 80 Entry3";
await fetch("https://api.ipify.org", {
  proxy: {
    url: "http://127.0.0.1:10801",
    headers: {
      "Proxy-Authorization": `Basic ${Buffer.from(`${vpnName}:`).toString(
        "base64"
      )}`,
    },
  },
});

// ✅ Random VPN - no auth needed
await fetch("https://api.ipify.org", {
  proxy: "http://127.0.0.1:10801",
});
```

### Node.js

Use the `https-proxy-agent` or `socks-proxy-agent` packages:

```typescript
import { HttpsProxyAgent } from "https-proxy-agent";

const vpnName = "AirVPN AT Vienna Alderamin UDP 80 Entry3";
const agent = new HttpsProxyAgent(
  `http://${encodeURIComponent(vpnName)}:@127.0.0.1:10801`
);

const response = await fetch("https://api.ipify.org", { agent });
```

### Python (requests)

```python
import requests

# Random VPN
response = requests.get(
    "https://api.ipify.org",
    proxies={"https": "http://127.0.0.1:10801"}
)

# Specific VPN
vpn_name = "AirVPN AT Vienna Alderamin UDP 80 Entry3"
response = requests.get(
    "https://api.ipify.org",
    proxies={"https": f"http://{vpn_name}:@127.0.0.1:10801"}
)
```

## Notifications

The proxy system sends desktop notifications for important events:

| Event                 | Notification                                      |
| --------------------- | ------------------------------------------------- |
| Invalid VPN slug      | "VPN not found: \<slug\>" with fallback to random |
| VPN connection failed | Error details with namespace info                 |
| Random VPN rotation   | New VPN name (if `VPN_PROXY_NOTIFY_ROTATION=1`)   |

**Implementation:** Notifications use Quickshell's IPC system (`qs-notify`)
which works from systemd services without D-Bus session access. This is more
reliable than `notify-send` in headless/service contexts.

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

1. **Kill-switch is mandatory**: All VPN traffic is blocked if VPN drops
2. **DNS isolation**: Each namespace has its own resolvers
3. **No credential storage**: VPN configs are read-only from disk
4. **tmpfs state**: Sensitive data never persists to disk
5. **Namespace isolation**: VPNs cannot interfere with each other
6. **localhost-only**: Proxies only listen on `127.0.0.1`
7. **"none" mode has no kill-switch**: Direct namespaces intentionally skip
   the kill-switch since there is no VPN to protect

## Performance Notes

- **Namespace creation**: ~3-5 seconds (OpenVPN handshake)
- **Direct namespace**: ~0.5 seconds (no VPN handshake needed)
- **First request**: May be slow while namespace is created
- **Subsequent requests**: Fast (reuses existing namespace)
- **Idle cleanup**: 5 minutes default (configurable)
- **Random rotation**: 5 minutes default (configurable)
- **Memory per namespace**: ~10-20MB (OpenVPN + microsocks)
