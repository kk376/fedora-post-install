# ==============================================================================
# Step 14: Gaming Stack (Steam, MangoHud, GameMode, Heroic)
# ==============================================================================
setup_gaming() {
    log "Installing Gaming Stack (Steam, MangoHud, GameMode, Heroic)..."

    local arch="${SYS_ARCH:-$(uname -m)}"
    local gaming_pkgs=("mangohud" "gamemode" "vulkan-tools")
    if [[ "$arch" == "x86_64" ]]; then
        gaming_pkgs+=("steam")
    else
        info "Note: Steam RPM packages are x86_64 exclusive (current arch: $arch)."
    fi

    run_sudo dnf install -y --skip-unavailable "${gaming_pkgs[@]}"

    if [[ "$arch" == "x86_64" ]]; then
        if ! $DRY_RUN; then
            local extra_steam_pkgs=("mozilla-openh264")
            if [[ "${IS_VM:-false}" != "true" && "${IS_CONTAINER:-false}" != "true" ]]; then
                extra_steam_pkgs=("steam-devices" "mozilla-openh264")
            fi
            run_sudo dnf install -y --skip-unavailable "${extra_steam_pkgs[@]}" 2>/dev/null || true
        else
            dry "Unlock Steam H264 codec"
        fi
    fi

    if ! $DRY_RUN; then
        mkdir -p "$HOME/.config/MangoHud"
        backup_file "$HOME/.config/MangoHud/MangoHud.conf"
        cat > "$HOME/.config/MangoHud/MangoHud.conf" <<'EOF'
gpu_stats
gpu_temp
gpu_core_clock
gpu_mem_clock
gpu_power
cpu_stats
cpu_temp
cpu_mhz
cpu_power
vram
ram
fps
frametime=1
frame_timing=1
hud_no_margin
table_columns=3
background_alpha=0.4
font_size=24
round_corners=8
EOF
        success "MangoHud configuration deployed"
    else
        dry "Create ~/.config/MangoHud/MangoHud.conf"
    fi

    if confirm "Install Heroic Games Launcher via Flathub?" "Y"; then
        if ! $DRY_RUN; then
            run flatpak install -y flathub com.heroicgameslauncher.hgl 2>/dev/null || warn "Heroic Flatpak install failed"
            mkdir -p "$HOME/Games/Heroic/Prefixes/shared" "$HOME/.var/app/com.heroicgameslauncher.hgl/config/MangoHud"
            if [[ -f "$HOME/.config/MangoHud/MangoHud.conf" ]]; then
                cp -p "$HOME/.config/MangoHud/MangoHud.conf" "$HOME/.var/app/com.heroicgameslauncher.hgl/config/MangoHud/MangoHud.conf" 2>/dev/null || true
            fi
        else
            dry "Install Heroic Games Launcher Flatpak and sync MangoHud config"
        fi
    fi

    step_complete "Gaming stack configured"
}

