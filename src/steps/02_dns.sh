# ==============================================================================
# Step 2: DNS Configuration
# ==============================================================================
setup_dns() {
    if $DRY_RUN; then
        dry "Configure custom DNS on active physical NetworkManager connections"
        step_complete "DNS (dry-run)"
        return 0
    fi

    echo ""
    log "DNS Configuration"
    info "Custom DNS replaces ISP resolvers with fast, privacy-respecting resolvers."
    info "Note: Skip if you use strict corporate VPNs or captive college portals."
    if ! confirm "Configure custom DNS resolvers?" "Y"; then
        info "Keeping default DHCP/ISP DNS settings"
        step_complete "DNS (skipped)"
        return 0
    fi

    echo "Choose a DNS provider:"
    echo "  1) Cloudflare DNS (1.1.1.1, 1.0.0.1) [default]"
    echo "  2) Google DNS (8.8.8.8, 8.8.4.4)"
    echo "  3) Quad9 Security DNS (9.9.9.9, 149.112.112.112)"
    echo "  4) Skip (keep current DNS)"

    local dns_choice DNS_IPV4 DNS_IPV6 DNS_NAME
    dns_choice=$(prompt_input "Select [1-4] (default: 1): " "1")

    case "$dns_choice" in
        2) DNS_IPV4="8.8.8.8 8.8.4.4"; DNS_IPV6="2001:4860:4860::8888 2001:4860:4860::8844"; DNS_NAME="Google" ;;
        3) DNS_IPV4="9.9.9.9 149.112.112.112"; DNS_IPV6="2620:fe::fe 2620:fe::9"; DNS_NAME="Quad9" ;;
        4) info "Keeping current DNS settings"; step_complete "DNS (skipped)"; return 0 ;;
        *) DNS_IPV4="1.1.1.1 1.0.0.1"; DNS_IPV6="2606:4700:4700::1111 2606:4700:4700::1001"; DNS_NAME="Cloudflare" ;;
    esac

    log "Applying $DNS_NAME DNS to active connections..."
    local conns
    conns=$(nmcli -t -f NAME connection show --active 2>/dev/null || true)
    while IFS= read -r conn; do
        [[ -z "$conn" ]] && continue
        if [[ "$conn" =~ ^(docker|lo|virbr|veth|br-|tailscale|wg) ]]; then
            info "Skipping virtual/tunnel interface: $conn"
            continue
        fi
        log "Setting DNS for: $conn"
        nmcli connection modify "$conn" ipv4.ignore-auto-dns yes ipv4.dns "$DNS_IPV4" 2>/dev/null || warn "Failed to set IPv4 DNS for $conn"
        nmcli connection modify "$conn" ipv6.ignore-auto-dns yes ipv6.dns "$DNS_IPV6" 2>/dev/null || warn "Failed to set IPv6 DNS for $conn"
        nmcli connection up "$conn" 2>/dev/null || warn "Failed to reload connection $conn"
    done <<< "$conns"

    step_complete "$DNS_NAME DNS configured"
}

