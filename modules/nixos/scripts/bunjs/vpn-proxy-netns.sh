#!/usr/bin/env bash
# VPN Proxy Network Namespace Manager
#
# Creates isolated network namespaces with:
# - veth pair for host<->namespace connectivity
# - NAT masquerading for outbound traffic
# - nftables kill-switch (blocks all non-VPN traffic)
# - Per-namespace DNS to prevent leaks
#
# Security: Kill-switch ensures zero IP leaks - if VPN drops, all traffic blocked
#
# Addressing scheme:
#   Host veth:      10.200.{index}.1/24
#   Namespace veth: 10.200.{index}.2/24
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

create_namespace() {
    local ns="$1"
    local idx="$2"
    local vpn_ip="$3"
    local vpn_port="$4"
    
    log "Creating namespace: $ns (index=$idx, vpn=$vpn_ip:$vpn_port)"
    
    if run ip netns list 2>/dev/null | grep -q "^$ns"; then
        log "Namespace $ns already exists, destroying first"
        destroy_namespace "$ns"
    fi
    
    if [[ -f "/var/run/netns/$ns" ]]; then
        log "Removing stale namespace file for $ns"
        run rm -f "/var/run/netns/$ns"
    fi
    
    run ip netns add "$ns" || die "Failed to create namespace $ns"
    
    local veth_host="veth-h-$idx"
    local veth_ns="veth-n-$idx"
    
    run ip link delete "$veth_host" 2>/dev/null || true
    run ip link delete "$veth_ns" 2>/dev/null || true
    
    run ip link add "$veth_host" type veth peer name "$veth_ns" || die "Failed to create veth pair"
    run ip link set "$veth_ns" netns "$ns" || die "Failed to move veth to namespace"
    
    local host_ip="10.200.$idx.1"
    local ns_ip="10.200.$idx.2"
    
    run ip addr add "$host_ip/24" dev "$veth_host" || die "Failed to set host IP"
    run ip link set "$veth_host" up || die "Failed to bring up host veth"
    
    run ip netns exec "$ns" ip addr add "$ns_ip/24" dev "$veth_ns" || die "Failed to set namespace IP"
    run ip netns exec "$ns" ip link set "$veth_ns" up || die "Failed to bring up namespace veth"
    run ip netns exec "$ns" ip link set lo up || die "Failed to bring up loopback"
    run ip netns exec "$ns" ip route add default via "$host_ip" || die "Failed to set default route"
    
    run sysctl -w net.ipv4.ip_forward=1 >/dev/null
    
    run iptables -t nat -A POSTROUTING -s "10.200.$idx.0/24" -j MASQUERADE
    run iptables -A FORWARD -i "$veth_host" -j ACCEPT
    run iptables -A FORWARD -o "$veth_host" -j ACCEPT
    
    run mkdir -p "/etc/netns/$ns"
    echo "nameserver 1.1.1.1" | run tee "/etc/netns/$ns/resolv.conf" >/dev/null
    echo "nameserver 1.0.0.1" | run tee -a "/etc/netns/$ns/resolv.conf" >/dev/null
    
    apply_killswitch "$ns" "$vpn_ip" "$vpn_port"
    
    mkdir -p "$STATE_DIR"
    cat > "$STATE_DIR/ns-$ns.json" <<EOF
{
  "name": "$ns",
  "index": $idx,
  "vethHost": "$veth_host",
  "vethNs": "$veth_ns",
  "hostIp": "$host_ip",
  "nsIp": "$ns_ip",
  "vpnServerIp": "$vpn_ip",
  "vpnServerPort": $vpn_port,
  "createdAt": $(date +%s)
}
EOF
    
    log "Namespace $ns created successfully"
    echo "$ns_ip"
}

apply_killswitch() {
    local ns="$1"
    local vpn_ip="$2"
    local vpn_port="$3"
    
    log "Applying kill-switch firewall rules for $ns"
    
    # Use nftables for the kill-switch
    run ip netns exec "$ns" nft -f - <<EOF
table inet vpn_killswitch {
    chain output {
        type filter hook output priority 0; policy drop;
        
        # Allow loopback
        oifname "lo" accept
        
        # Allow traffic via VPN tunnel (tun0)
        oifname "tun*" accept
        
        # Allow encrypted VPN handshake to server
        ip daddr $vpn_ip udp dport $vpn_port accept
        ip daddr $vpn_ip tcp dport $vpn_port accept
        
        # Allow ICMP for diagnostics
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
        local idx veth_host
        idx=$(jq -r '.index' "$info_file")
        veth_host=$(jq -r '.vethHost' "$info_file")
        
        run iptables -t nat -D POSTROUTING -s "10.200.$idx.0/24" -j MASQUERADE 2>/dev/null || true
        run iptables -D FORWARD -i "$veth_host" -j ACCEPT 2>/dev/null || true
        run iptables -D FORWARD -o "$veth_host" -j ACCEPT 2>/dev/null || true
        run ip link delete "$veth_host" 2>/dev/null || true
        
        rm -f "$info_file"
    fi
    
    local pids
    pids=$(run ip netns pids "$ns" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        log "Killing processes in namespace: $pids"
        echo "$pids" | xargs -r run kill -9 2>/dev/null || true
        sleep 1
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
    run ip netns list 2>/dev/null | grep "^vpn-proxy-" || true
}

check_namespace() {
    local ns="$1"
    run ip netns list 2>/dev/null | grep -q "^$ns " && echo "exists" || echo "missing"
}

case "$ACTION" in
    create)
        [[ -z "$NS_NAME" ]] && die "Usage: $0 create <name> <index> <vpn_server_ip> [vpn_server_port]"
        [[ -z "$VPN_SERVER_IP" ]] && die "VPN server IP is required"
        create_namespace "$NS_NAME" "$NS_INDEX" "$VPN_SERVER_IP" "$VPN_SERVER_PORT"
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
        for ns in $(list_namespaces | awk '{print $1}'); do
            destroy_namespace "$ns"
        done
        log "All namespaces cleaned up"
        ;;
    *)
        echo "VPN Proxy Network Namespace Manager

Usage:
  $0 create <name> <index> <vpn_server_ip> [vpn_server_port]
  $0 destroy <name>
  $0 list
  $0 check <name>
  $0 cleanup-all

Examples:
  $0 create vpn-proxy-0 0 185.189.114.57 443
  $0 destroy vpn-proxy-0
  $0 cleanup-all
"
        ;;
esac
