#!/usr/bin/env bash
# Network namespace setup for VPN SOCKS5 proxy isolation
# Creates isolated network environment with kill-switch firewall rules

set -euo pipefail

ACTION="${1:-}"
NS_NAME="${2:-}"
NS_INDEX="${3:-0}"
VPN_SERVER_IP="${4:-}"
VPN_SERVER_PORT="${5:-1194}"

STATE_DIR="/dev/shm/vpn-proxy-$(id -u)"
LOG_PREFIX="[netns-setup]"

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
    
    # Create the namespace
    sudo ip netns add "$ns" || die "Failed to create namespace $ns"
    
    # Create veth pair
    local veth_host="veth-h-$idx"
    local veth_ns="veth-n-$idx"
    
    sudo ip link add "$veth_host" type veth peer name "$veth_ns" || die "Failed to create veth pair"
    
    # Move one end into namespace
    sudo ip link set "$veth_ns" netns "$ns" || die "Failed to move veth to namespace"
    
    # Configure host-side IP (10.200.X.1/24)
    local host_ip="10.200.$idx.1"
    local ns_ip="10.200.$idx.2"
    
    sudo ip addr add "$host_ip/24" dev "$veth_host" || die "Failed to set host IP"
    sudo ip link set "$veth_host" up || die "Failed to bring up host veth"
    
    # Configure namespace-side
    sudo ip netns exec "$ns" ip addr add "$ns_ip/24" dev "$veth_ns" || die "Failed to set namespace IP"
    sudo ip netns exec "$ns" ip link set "$veth_ns" up || die "Failed to bring up namespace veth"
    sudo ip netns exec "$ns" ip link set lo up || die "Failed to bring up loopback"
    
    # Set default route in namespace to go through host (for VPN handshake)
    sudo ip netns exec "$ns" ip route add default via "$host_ip" || die "Failed to set default route"
    
    # Enable IP forwarding on host
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
    
    # NAT masquerade for namespace traffic
    sudo iptables -t nat -A POSTROUTING -s "10.200.$idx.0/24" -j MASQUERADE
    sudo iptables -A FORWARD -i "$veth_host" -j ACCEPT
    sudo iptables -A FORWARD -o "$veth_host" -j ACCEPT
    
    # Create per-namespace DNS config (prevents DNS leaks)
    sudo mkdir -p "/etc/netns/$ns"
    echo "nameserver 1.1.1.1" | sudo tee "/etc/netns/$ns/resolv.conf" >/dev/null
    echo "nameserver 1.0.0.1" | sudo tee -a "/etc/netns/$ns/resolv.conf" >/dev/null
    
    # Apply kill-switch firewall rules inside namespace
    apply_killswitch "$ns" "$vpn_ip" "$vpn_port"
    
    # Save namespace info
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
    sudo ip netns exec "$ns" nft -f - <<EOF
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
    
    # Load namespace info
    local info_file="$STATE_DIR/ns-$ns.json"
    if [[ -f "$info_file" ]]; then
        local idx veth_host
        idx=$(jq -r '.index' "$info_file")
        veth_host=$(jq -r '.vethHost' "$info_file")
        
        # Remove NAT rules
        sudo iptables -t nat -D POSTROUTING -s "10.200.$idx.0/24" -j MASQUERADE 2>/dev/null || true
        sudo iptables -D FORWARD -i "$veth_host" -j ACCEPT 2>/dev/null || true
        sudo iptables -D FORWARD -o "$veth_host" -j ACCEPT 2>/dev/null || true
        
        # Remove veth from host
        sudo ip link delete "$veth_host" 2>/dev/null || true
        
        rm -f "$info_file"
    fi
    
    # Kill all processes in namespace
    local pids
    pids=$(sudo ip netns pids "$ns" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        log "Killing processes in namespace: $pids"
        echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
        sleep 0.5
    fi
    
    # Delete namespace
    sudo ip netns delete "$ns" 2>/dev/null || true
    
    # Remove DNS config
    sudo rm -rf "/etc/netns/$ns" 2>/dev/null || true
    
    log "Namespace $ns destroyed"
}

list_namespaces() {
    sudo ip netns list 2>/dev/null | grep "^vpn-proxy-" || true
}

check_namespace() {
    local ns="$1"
    sudo ip netns list 2>/dev/null | grep -q "^$ns " && echo "exists" || echo "missing"
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
