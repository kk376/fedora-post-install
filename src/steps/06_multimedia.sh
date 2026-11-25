# ==============================================================================
# Step 6: Multimedia Codecs & PipeWire/WirePlumber Audio
# ==============================================================================
setup_multimedia() {
    log "Configuring multimedia codecs, hardware VA-API, and PipeWire audio..."

    if rpm -q ffmpeg-free &>/dev/null; then
        run_sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    else
        run_sudo dnf install -y --skip-unavailable ffmpeg
    fi
    local mm_pkgs=(
        gstreamer1-plugins-bad-freeworld
        gstreamer1-plugins-ugly
        gstreamer1-plugin-openh264
        mozilla-openh264
    )
    if [[ "${HAS_INTEL:-false}" == "true" || "${HAS_AMD:-false}" == "true" || "${HAS_NVIDIA:-false}" == "true" ]]; then
        mm_pkgs+=("libva-utils")
    fi
    run_sudo dnf install -y --allowerasing "${mm_pkgs[@]}" 2>/dev/null || warn "Some multimedia packages failed to install"

    run_sudo dnf group install -y --with-optional multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin 2>/dev/null || \
        warn "Multimedia group install had partial warnings (non-critical)"

    local bt_restart=false
    if [[ "${HAS_BLUETOOTH:-false}" == "true" ]]; then
        log "Bluetooth adapter detected: Configuring WirePlumber Bluetooth HD audio..."
        if ! $DRY_RUN; then
            backup_file "/etc/wireplumber/wireplumber.conf.d/50-bluez.conf"
            run_sudo mkdir -p /etc/wireplumber/wireplumber.conf.d
            run_sudo tee /etc/wireplumber/wireplumber.conf.d/50-bluez.conf > /dev/null <<'BLUEZ_CONF'
monitor.bluez.properties = {
  bluez5.roles = [ a2dp_sink a2dp_source hfp_hf hfp_ag ]
  bluez5.codecs = [ ldac aac aptx_hd aptx sbc_xq sbc ]
  bluez5.enable-sbc-xq = true
  bluez5.enable-msbc = true
  bluez5.enable-hw-volume = true
}

wireplumber.settings = {
  bluetooth.autoswitch-to-headset-profile = false
}
BLUEZ_CONF

            # Prevent GDM from hijacking Bluetooth headphones before user login
            if id gdm &>/dev/null; then
                backup_file "/var/lib/gdm/.config/wireplumber/wireplumber.conf.d/disable-bluetooth.conf"
                run_sudo mkdir -p /var/lib/gdm/.config/wireplumber/wireplumber.conf.d
                run_sudo tee /var/lib/gdm/.config/wireplumber/wireplumber.conf.d/disable-bluetooth.conf > /dev/null <<'GDM_BT_CONF'
wireplumber.profiles = {
  main = {
    hardware.bluetooth = disabled
  }
}
GDM_BT_CONF
                run_sudo chown -R gdm:gdm /var/lib/gdm/.config/wireplumber 2>/dev/null || true
            fi
            bt_restart=true
            success "WirePlumber Bluetooth HD audio configured"
        else
            dry "Deploy WirePlumber Bluetooth HD config"
        fi
    else
        info "No Bluetooth hardware detected: Skipping WirePlumber Bluetooth audio tuning."
    fi

    if confirm "Enable PipeWire multi-rate sample switching (44.1kHz-192kHz for hi-res DACs)?" "N"; then
        if ! $DRY_RUN; then
            backup_file "/etc/pipewire/pipewire.conf.d/99-clock-rates.conf"
            run_sudo mkdir -p /etc/pipewire/pipewire.conf.d
            run_sudo tee /etc/pipewire/pipewire.conf.d/99-clock-rates.conf > /dev/null <<'CLOCK_CONF'
context.properties = {
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]
}
CLOCK_CONF
            bt_restart=true
            success "PipeWire dynamic sample rates configured"
        else
            dry "Deploy PipeWire dynamic clock rate config"
        fi
    fi

    if ! $DRY_RUN && $bt_restart && systemctl --user is-active wireplumber &>/dev/null; then
        systemctl --user restart pipewire wireplumber 2>/dev/null || true
    fi

    step_complete "Multimedia & audio configured"
}

