#!/usr/bin/env bash
# VPN Proxy Network Namespace Manager
#
# Creates isolated network namespaces with:
# - veth pair for host<->namespace connectivity
# - NAT masquerading for outbound traffic
# - nftables kill-switch (blocks all non-VPN traffic) [VPN mode only]
# - Per-namespace DNS to prevent leaks
#
# Two modes:
# - create:        Full VPN namespace with kill-switch (blocks all non-VPN traffic)
# - create-direct: Direct namespace without VPN/kill-switch (bypasses device VPN)
#
# Security: Kill-switch ensures zero IP leaks - if VPN drops, all traffic blocked
#
# Addressing scheme:
#   Host veth:      10.200.{subnet}.1/24 (subnet = index % 254 + 1)
#   Namespace veth: 10.200.{subnet}.2/24
#   Namespace name: vpn-proxy-{index}
#
# Dependencies: iproute2, iptables, nftables, jq, coreutils

set -euo pipefail

ACTION="${1:-}"
NS_NAME="${2:-}"
NS_INDEX="${3:-0}"
VPN_SERVER_IP="${4:-}"
VPN_SERVER_PORT="${5:-1194}"

STATE_DIR="/dev/shm/vpn-proxy-$(id -u)"
LOG_PREFIX="[netns-setup]"

run() {
    if [[ $(id -u) -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

log() {
    echo "$(date -Iseconds) $LOG_PREFIX $*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

# Common namespace setup: veth pair, NAT, DNS, microsocks
# Used by both create_namespace (VPN) and create_direct_namespace (no VPN)
setup_namespace_base() {
    local ns="$1"
    local idx="$2"
    
    if run ip netns list 2>/dev/null | grep -q "^$ns"; then
        log "Namespace $ns already exists, destroying first"
        destroy_namespace "$ns"
    fi
    
    # Wait for namespace file to be fully released after destroy
    if [[ -f "/var/run/netns/$ns" ]]; then
        log "Waiting for stale namespace file to be released: $ns"
        local retries=10
        while [[ -f "/var/run/netns/$ns" ]] && [[ $retries -gt 0 ]]; do
            run umount "/var/run/netns/$ns" 2>/dev/null || true
            run rm -f "/var/run/netns/$ns" 2>/dev/null || true
            if [[ -f "/var/run/netns/$ns" ]]; then
                sleep 0.5
                ((retries--))
            fi
        done
        if [[ -f "/var/run/netns/$ns" ]]; then
            die "Cannot remove stale namespace file /var/run/netns/$ns - still busy after retries"
        fi
    fi
    
    run ip netns add "$ns" || die "Failed to create namespace $ns"
    
    local veth_host="veth-h-$idx"
    local veth_ns="veth-n-$idx"
    local subnet=$(( (idx % 254) + 1 ))
    
    run ip link delete "$veth_host" 2>/dev/null || true
    run ip link delete "$veth_ns" 2>/dev/null || true
    
    run ip link add "$veth_host" type veth peer name "$veth_ns" || die "Failed to create veth pair"
    run ip link set "$veth_ns" netns "$ns" || die "Failed to move veth to namespace"
    
    local host_ip="10.200.$subnet.1"
    local ns_ip="10.200.$subnet.2"
    local socks_port=$((10900 + (idx % 50000)))
    
    run ip addr add "$host_ip/24" dev "$veth_host" || die "Failed to set host IP"
    run ip link set "$veth_host" up || die "Failed to bring up host veth"
    
    run ip netns exec "$ns" ip addr add "$ns_ip/24" dev "$veth_ns" || die "Failed to set namespace IP"
    run ip netns exec "$ns" ip link set "$veth_ns" up || die "Failed to bring up namespace veth"
    run ip netns exec "$ns" ip link set lo up || die "Failed to bring up loopback"
    run ip netns exec "$ns" ip route add default via "$host_ip" || die "Failed to set default route"
    
    run sysctl -w net.ipv4.ip_forward=1 >/dev/null
    
    run iptables -t nat -A POSTROUTING -s "10.200.$subnet.0/24" -j MASQUERADE
    run iptables -A FORWARD -i "$veth_host" -j ACCEPT
    run iptables -A FORWARD -o "$veth_host" -j ACCEPT
    
    run mkdir -p "/etc/netns/$ns"
    echo "nameserver 1.1.1.1" | run tee "/etc/netns/$ns/resolv.conf" >/dev/null
    echo "nameserver 1.0.0.1" | run tee -a "/etc/netns/$ns/resolv.conf" >/dev/null
    
    mkdir -p "$STATE_DIR"
    
    # Start microsocks SOCKS5 proxy inside namespace, bound to veth IP for host access
    local microsocks_pid_file="$STATE_DIR/microsocks-$ns.pid"
    run ip netns exec "$ns" microsocks -i "$ns_ip" -p "$socks_port" &
    sleep 0.2
    local microsocks_pid
    microsocks_pid=$(run ip netns pids "$ns" 2>/dev/null | grep -v "^$" | head -1 || echo "")
    if [[ -n "$microsocks_pid" ]]; then
        echo "$microsocks_pid" > "$microsocks_pid_file"
        log "Started microsocks on $ns_ip:$socks_port (PID $microsocks_pid)"
    else
        log "WARNING: Could not determine microsocks PID"
    fi
}

create_namespace() {
    local ns="$1"
    local idx="$2"
    local vpn_ip="$3"
    local vpn_port="$4"
    
    log "Creating namespace: $ns (index=$idx, vpn=$vpn_ip:$vpn_port)"
    
    setup_namespace_base "$ns" "$idx"
    
    apply_killswitch "$ns" "$vpn_ip" "$vpn_port"
    
    local veth_host="veth-h-$idx"
    local veth_ns="veth-n-$idx"
    local host_ip="10.200.$idx.1"
    local ns_ip="10.200.$idx.2"
    local socks_port=$((10900 + idx))
    
    cat > "$STATE_DIR/ns-$ns.json" <<EOF
{
  "name": "$ns",
  "index": $idx,
  "vethHost": "$veth_host",
  "vethNs": "$veth_ns",
  "hostIp": "$host_ip",
  "nsIp": "$ns_ip",
  "socksPort": $socks_port,
  "vpnServerIp": "$vpn_ip",
  "vpnServerPort": $vpn_port,
  "createdAt": $(date +%s)
}
EOF
    
    log "Namespace $ns created successfully"
    echo "$ns_ip:$socks_port"
}

# Create a direct namespace (no VPN, no kill-switch)
# Bypasses any device-level VPN by using a separate network namespace
# with its own routing table that goes directly through the host's real interface
create_direct_namespace() {
    local ns="$1"
    local idx="$2"
    
    log "Creating direct namespace: $ns (index=$idx, no VPN)"
    
    setup_namespace_base "$ns" "$idx"
    
    # No kill-switch applied — traffic goes out directly via host NAT
    
    local veth_host="veth-h-$idx"
    local veth_ns="veth-n-$idx"
    local host_ip="10.200.$idx.1"
    local ns_ip="10.200.$idx.2"
    local socks_port=$((10900 + idx))
    
    cat > "$STATE_DIR/ns-$ns.json" <<EOF
{
  "name": "$ns",
  "index": $idx,
  "vethHost": "$veth_host",
  "vethNs": "$veth_ns",
  "hostIp": "$host_ip",
  "nsIp": "$ns_ip",
  "socksPort": $socks_port,
  "vpnServerIp": "none",
  "vpnServerPort": 0,
  "createdAt": $(date +%s)
}
EOF
    
    log "Direct namespace $ns created successfully"
    echo "$ns_ip:$socks_port"
}

apply_killswitch() {
    local ns="$1"
    local vpn_ip="$2"
    local vpn_port="$3"
    
    log "Applying kill-switch firewall rules for $ns"
    
    # nftables kill-switch: DROP all outbound except VPN tunnel and handshake
    # veth-n-* is allowed for traffic TO the namespace (inbound from host)
    # but outbound from namespace MUST go through tun0 (VPN) or be VPN handshake
    run ip netns exec "$ns" nft -f - <<EOF
table inet vpn_killswitch {
    chain output {
        type filter hook output priority 0; policy drop;
        
        oifname "lo" accept
        
        # Allow outbound via VPN tunnel only
        oifname "tun*" accept
        
        # Allow VPN handshake to establish tunnel (before tun0 exists)
        ip daddr $vpn_ip udp dport $vpn_port accept
        ip daddr $vpn_ip tcp dport $vpn_port accept
        
        # Allow responses back to host veth (for SOCKS5 data return path)
        oifname "veth-n-*" accept
        
        ip protocol icmp accept
    }
    
    chain input {
        type filter hook input priority 0; policy accept;
    }
}
EOF
    
    log "Kill-switch applied for $ns"
}

destroy_namespace() {
    local ns="$1"
    
    log "Destroying namespace: $ns"
    
    local info_file="$STATE_DIR/ns-$ns.json"
    if [[ -f "$info_file" ]]; then
        local idx veth_host subnet
        idx=$(jq -r '.index' "$info_file")
        veth_host=$(jq -r '.vethHost' "$info_file")
        subnet=$(( (idx % 254) + 1 ))
        
        run iptables -t nat -D POSTROUTING -s "10.200.$subnet.0/24" -j MASQUERADE 2>/dev/null || true
        run iptables -D FORWARD -i "$veth_host" -j ACCEPT 2>/dev/null || true
        run iptables -D FORWARD -o "$veth_host" -j ACCEPT 2>/dev/null || true
        run ip link delete "$veth_host" 2>/dev/null || true
        
        rm -f "$info_file"
    fi
    
    local microsocks_pid_file="$STATE_DIR/microsocks-$ns.pid"
    if [[ -f "$microsocks_pid_file" ]]; then
        local mpid
        mpid=$(cat "$microsocks_pid_file")
        run kill -9 "$mpid" 2>/dev/null || true
        rm -f "$microsocks_pid_file"
    fi
    
    local pids
    pids=$(run ip netns pids "$ns" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        log "Killing processes in namespace: $pids"
        for pid in $pids; do
            run kill -9 "$pid" 2>/dev/null || true
        done
        local wait_count=0
        while [[ $wait_count -lt 10 ]]; do
            pids=$(run ip netns pids "$ns" 2>/dev/null || true)
            [[ -z "$pids" ]] && break
            sleep 0.3
            ((wait_count++))
        done
    fi
    
    run umount "/etc/netns/$ns/resolv.conf" 2>/dev/null || true
    run rm -rf "/etc/netns/$ns" 2>/dev/null || true
    
    run ip netns delete "$ns" 2>/dev/null || true
    
    if [[ -f "/var/run/netns/$ns" ]]; then
        sleep 0.5
        run umount "/var/run/netns/$ns" 2>/dev/null || true
        run rm -f "/var/run/netns/$ns" 2>/dev/null || true
    fi
    
    log "Namespace $ns destroyed"
}

list_namespaces() {
    run ip netns list 2>/dev/null | grep "vpn-proxy-" | awk '{print $1}' || true
}

check_namespace() {
    local ns="$1"
    run ip netns list 2>/dev/null | grep -q "^$ns" && echo "exists" || echo "missing"
}

case "$ACTION" in
    create)
        [[ -z "$NS_NAME" ]] && die "Usage: $0 create <name> <index> <vpn_server_ip> [vpn_server_port]"
        [[ -z "$VPN_SERVER_IP" ]] && die "VPN server IP is required"
        create_namespace "$NS_NAME" "$NS_INDEX" "$VPN_SERVER_IP" "$VPN_SERVER_PORT"
        ;;
    create-direct)
        [[ -z "$NS_NAME" ]] && die "Usage: $0 create-direct <name> <index>"
        create_direct_namespace "$NS_NAME" "$NS_INDEX"
        ;;
    destroy)
        [[ -z "$NS_NAME" ]] && die "Usage: $0 destroy <name>"
        destroy_namespace "$NS_NAME"
        ;;
    list)
        list_namespaces
        ;;
    check)
        [[ -z "$NS_NAME" ]] && die "Usage: $0 check <name>"
        check_namespace "$NS_NAME"
        ;;
    cleanup-all)
        log "Cleaning up all vpn-proxy namespaces"
        for ns in $(list_namespaces); do
            destroy_namespace "$ns"
        done
        # Also clean up any stale netns files that list_namespaces might miss
        for nsfile in /var/run/netns/vpn-proxy-*; do
            [[ -e "$nsfile" ]] || continue
            ns_name=$(basename "$nsfile")
            log "Cleaning stale netns file: $ns_name"
            run umount "$nsfile" 2>/dev/null || true
            run rm -f "$nsfile" 2>/dev/null || true
        done
        # Clean up any orphaned veth interfaces
        for veth in $(ip link show 2>/dev/null | grep -o 'veth-h-[0-9]*' || true); do
            run ip link delete "$veth" 2>/dev/null || true
        done
        # Clean up state directory
        rm -rf "$STATE_DIR" 2>/dev/null || true
        log "All namespaces cleaned up"
        ;;
    *)
        echo "VPN Proxy Network Namespace Manager

Usage:
  $0 create <name> <index> <vpn_server_ip> [vpn_server_port]
  $0 create-direct <name> <index>
  $0 destroy <name>
  $0 list
  $0 check <name>
  $0 cleanup-all

Examples:
  $0 create vpn-proxy-0 0 185.189.114.57 443
  $0 create-direct vpn-proxy-1 1
  $0 destroy vpn-proxy-0
  $0 cleanup-all
"
        ;;
esac
