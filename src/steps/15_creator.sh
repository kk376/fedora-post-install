# ==============================================================================
# Step 15: Creator & Streaming Suite (OBS, v4l2loopback, Screen Recording)
# ==============================================================================
setup_creator() {
    log "Installing Creator & Streaming Suite..."

    local creator_pkgs=(
        obs-studio pulseaudio-utils gstreamer1-devel
    )
    run_sudo dnf install -y --skip-unavailable "${creator_pkgs[@]}"

    if [[ "${IS_CONTAINER:-false}" != "true" ]]; then
        if confirm "Install v4l2loopback kernel module for OBS Virtual Camera? (Requires akmods build)" "Y"; then
            run_sudo dnf install -y --skip-unavailable akmod-v4l2loopback v4l2loopback v4l-utils
            if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
                warn "Secure Boot is ENABLED: v4l2loopback requires MOK enrollment (sudo kmodgenca -a && sudo mokutil --import /etc/pki/akmods/certs/public_key.der) before modprobe succeeds."
            fi
        fi
    fi

    if $HAS_NVIDIA && confirm "Install NVIDIA Broadcast for Linux?" "N"; then
        local nb_dir="$HOME/.local/share/nvidia-broadcast-linux"
        if ! $DRY_RUN; then
            mkdir -p "$HOME/.local/share"
            if [[ ! -d "$nb_dir" ]]; then
                git clone --depth 1 --branch v1.5.2 https://github.com/Hkshoonya/nvidia-broadcast-linux.git "$nb_dir" || warn "Failed to clone nvidia-broadcast-linux"
            fi
            if [[ -f "$nb_dir/install.sh" ]]; then
                (cd "$nb_dir" && ./install.sh --runtime cuda) || warn "NVIDIA Broadcast install finished with warnings"
            fi
        else
            dry "Clone and install NVIDIA Broadcast for Linux"
        fi
    fi

    step_complete "Creator suite configured"
}

