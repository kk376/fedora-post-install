# ==============================================================================
# Step 9: Hardware-Aware Power & Sleep Management
# ==============================================================================
setup_power() {
    log "Configuring Power & Sleep policies..."

    if [[ "${IS_CONTAINER:-false}" == "true" ]]; then
        info "Container environment detected: Skipping host power daemon, sleep policy, and ZRAM sysctl tuning."
        step_complete "Power & sleep policies (skipped in container)"
        return 0
    fi

    if [[ "${IS_LAPTOP:-false}" == "true" ]] && [[ "${IS_VM:-false}" != "true" ]]; then
        info "Laptop chassis detected."
        info "Modern AMD/Intel laptops perform best with Fedora's default power daemon (tuned-ppd / power-profiles-daemon)."
        if confirm "Replace default power profiles with TLP anyway?" "N"; then
            run_sudo dnf install -y tlp tlp-rdw
            run_sudo systemctl mask power-profiles-daemon.service 2>/dev/null || true
            run_sudo systemctl mask tuned.service 2>/dev/null || true
            run_sudo systemctl mask tuned-ppd.service 2>/dev/null || true
            run_sudo systemctl stop power-profiles-daemon.service tuned.service tuned-ppd.service 2>/dev/null || true
            run_sudo systemctl enable --now tlp.service
            success "TLP enabled (power-profiles-daemon and tuned masked to prevent conflict)"
        else
            info "Keeping native Fedora power profile management"
        fi
    else
        info "Non-laptop chassis detected (${CHASSIS_TYPE:-Desktop}): Skipping laptop battery daemon (TLP)."
    fi

    # Safe No-Sleep: Disable auto-sleep on AC power, preserving battery suspend on laptops
    if confirm "Disable auto-suspend when plugged into AC power?" "Y"; then
        if ! $DRY_RUN; then
            run_sudo mkdir -p /etc/dconf/profile /etc/dconf/db/gdm.d
            if [[ ! -f /etc/dconf/profile/gdm ]]; then
                backup_file "/etc/dconf/profile/gdm"
                run_sudo tee /etc/dconf/profile/gdm > /dev/null <<'EOF'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
            fi
            backup_file "/etc/dconf/db/gdm.d/01-power"
            run_sudo tee /etc/dconf/db/gdm.d/01-power > /dev/null <<'EOF'
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-timeout=0
sleep-inactive-ac-type='nothing'
EOF
            run_sudo dconf update 2>/dev/null || true

            gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 2>/dev/null || true
            gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
            success "AC auto-suspend disabled (battery suspend preserved for safety)"
        else
            dry "Disable AC auto-suspend in GDM dconf and user gsettings"
        fi
    fi

    # High-Performance ZRAM & Kernel Memory Tuning (Dynamic RAM allocation, zstd)
    if confirm "Apply ZRAM memory tuning (zstd compression, swappiness 180)?" "Y"; then
        if ! $DRY_RUN; then
            run_sudo mkdir -p /etc/systemd/zram-generator.conf.d /etc/sysctl.d
            if [[ -f /etc/systemd/zram-generator.conf.d/10-zram.conf ]]; then
                backup_file "/etc/systemd/zram-generator.conf.d/10-zram.conf"
                run_sudo rm -f /etc/systemd/zram-generator.conf.d/10-zram.conf
            fi
            backup_file "/etc/systemd/zram-generator.conf.d/99-zram.conf"
            run_sudo tee /etc/systemd/zram-generator.conf.d/99-zram.conf > /dev/null <<'ZRAM_EOF'
[zram0]
zram-size = min(ram / 2, 32768)
compression-algorithm = zstd
ZRAM_EOF

            backup_file "/etc/sysctl.d/99-zram.conf"
            run_sudo tee /etc/sysctl.d/99-zram.conf > /dev/null <<'SYSCTL_EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
SYSCTL_EOF

            # Remove legacy monolithic config to avoid precedence conflict with drop-in
            if [[ -f /etc/systemd/zram-generator.conf ]]; then
                backup_file "/etc/systemd/zram-generator.conf"
                run_sudo rm -f /etc/systemd/zram-generator.conf
            fi

            run_sudo sysctl --system >/dev/null 2>&1 || true
            run_sudo systemctl daemon-reload 2>/dev/null || true
            success "High-performance ZRAM drop-in applied (/etc/systemd/zram-generator.conf.d/99-zram.conf; takes full effect on next reboot)"
        else
            dry "Configure /etc/systemd/zram-generator.conf.d/99-zram.conf (zstd, balanced RAM cap) and /etc/sysctl.d/99-zram.conf"
        fi
    fi

    step_complete "Power & sleep policies configured"
}

