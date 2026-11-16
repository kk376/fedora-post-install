# ==============================================================================
# Step 3: Core CLI Utilities
# ==============================================================================
setup_cli_core() {
    log "Installing essential CLI utilities..."

    local cli_pkgs=(
        fastfetch bat eza fd-find ripgrep fzf zoxide wget curl btop duf
        plocate tree compsize unzip unrar p7zip p7zip-plugins jq vim
        wl-clipboard xclip git android-tools
    )

    run_sudo dnf install -y --skip-unavailable "${cli_pkgs[@]}"

    step_complete "Core CLI utilities installed"
}

