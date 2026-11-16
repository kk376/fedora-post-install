# ==============================================================================
# Step 12: Docker & Compose Setup
# ==============================================================================
setup_docker() {
    log "Configuring Docker Engine & Compose..."

    run_sudo dnf install -y --skip-unavailable moby-engine docker-cli containerd docker-compose

    if ! rpm -q moby-engine &>/dev/null && ! rpm -q docker-ce &>/dev/null; then
        warn "Docker engine package not found - skipping daemon configuration"
        step_complete "Docker (skipped)"
        return 0
    fi

    # Tell NetworkManager to ignore docker0 to prevent route metric conflicts
    if ! $DRY_RUN && [[ ! -f /etc/NetworkManager/conf.d/10-docker.conf ]]; then
        run_sudo mkdir -p /etc/NetworkManager/conf.d
        run_sudo tee /etc/NetworkManager/conf.d/10-docker.conf >/dev/null <<'EOF'
[keyfile]
unmanaged-devices=interface-name:docker0
EOF
        run_sudo systemctl reload NetworkManager 2>/dev/null || true
    fi

    run_sudo usermod -aG docker "${USER:-$(id -un)}"
    run_sudo systemctl enable --now containerd.service docker.service 2>/dev/null || warn "Failed to start Docker daemon"

    # Architecture-aware Docker Compose CLI plugin fallback if RPM plugin isn't present
    if ! docker compose version &>/dev/null && ! $DRY_RUN; then
        local docker_config="${DOCKER_CONFIG:-$HOME/.docker}"
        mkdir -p "$docker_config/cli-plugins"
        if github_download "docker/compose" "docker-compose-linux-${SYS_ARCH}$" \
            "$docker_config/cli-plugins/docker-compose" \
            "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${SYS_ARCH}"; then
            chmod +x "$docker_config/cli-plugins/docker-compose"
            success "Docker Compose CLI plugin installed ($SYS_ARCH)"
        fi
    fi

    step_complete "Docker configured"
}

