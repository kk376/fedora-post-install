# ==============================================================================
# Step 2: Encrypted DNS-over-TLS (DoT) Configuration
# ==============================================================================
setup_dns() {
    if $DRY_RUN; then
        dry "Configure encrypted DNS-over-TLS (DoT) via systemd-resolved"
        step_complete "DNS (dry-run)"
        return 0
    fi

    echo ""
    log "DNS Configuration"
    info "DNS-over-TLS (DoT) encrypts all DNS lookups system-wide to prevent ISP eavesdropping."
    info "Note: Skip if you must use strict corporate VPNs or restrictive captive portals."
    if ! confirm "Configure encrypted DNS-over-TLS resolvers?" "Y"; then
        info "Keeping default DHCP/ISP DNS settings"
        step_complete "DNS (skipped)"
        return 0
    fi

    echo "Choose a DNS provider:"
    echo "  1) Cloudflare DNS-over-TLS (1.1.1.1, 1.0.0.1) [default]"
    echo "  2) Quad9 Security DNS-over-TLS (9.9.9.9, 149.112.112.112 - malware blocking)"
    echo "  3) Google DNS-over-TLS (8.8.8.8, 8.8.4.4)"
    echo "  4) Skip (keep current DNS)"

    local dns_choice DNS_SERVERS FALLBACK_SERVERS DNS_NAME
    dns_choice=$(prompt_input "Select [1-4] (default: 1): " "1")

    case "$dns_choice" in
        2)
            DNS_SERVERS="9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net"
            FALLBACK_SERVERS="1.1.1.1#cloudflare-dns.com 8.8.8.8#dns.google"
            DNS_NAME="Quad9"
            ;;
        3)
            DNS_SERVERS="8.8.8.8#dns.google 8.8.4.4#dns.google 2001:4860:4860::8888#dns.google 2001:4860:4860::8844#dns.google"
            FALLBACK_SERVERS="1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net"
            DNS_NAME="Google"
            ;;
        4)
            info "Keeping current DNS settings"
            step_complete "DNS (skipped)"
            return 0
            ;;
        *)
            DNS_SERVERS="1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com 2606:4700:4700::1001#cloudflare-dns.com"
            FALLBACK_SERVERS="9.9.9.9#dns.quad9.net 8.8.8.8#dns.google"
            DNS_NAME="Cloudflare"
            ;;
    esac

    log "Deploying system-wide DNS-over-TLS ($DNS_NAME)..."
    run_sudo mkdir -p /etc/systemd/resolved.conf.d /etc/NetworkManager/conf.d

    run_sudo tee /etc/systemd/resolved.conf.d/10-dot.conf > /dev/null <<EOF
# Managed by Fedora Post-Install Setup Script
[Resolve]
DNS=$DNS_SERVERS
FallbackDNS=$FALLBACK_SERVERS
Domains=~.
DNSOverTLS=opportunistic
DNSSEC=no
EOF

    run_sudo tee /etc/NetworkManager/conf.d/10-dns.conf > /dev/null <<EOF
# Direct NetworkManager to delegate name resolution to systemd-resolved
[main]
dns=systemd-resolved
EOF

    log "Restarting systemd-resolved and reloading NetworkManager..."
    run_sudo systemctl enable --now systemd-resolved 2>/dev/null || true
    run_sudo systemctl restart systemd-resolved 2>/dev/null || true
    run_sudo systemctl reload NetworkManager 2>/dev/null || true

    step_complete "Encrypted $DNS_NAME DNS-over-TLS configured"
}
