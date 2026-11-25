# ==============================================================================
# Step 3: Core CLI Utilities
# ==============================================================================
setup_cli_core() {
    log "Installing essential CLI utilities..."

    local cli_pkgs=(
        fastfetch bat eza fd-find ripgrep fzf zoxide wget curl btop duf
        plocate tree unzip unrar p7zip p7zip-plugins 7zip jq vim
        wl-clipboard git android-tools yt-dlp
    )
    [[ "${HAS_BTRFS:-false}" == "true" ]] && cli_pkgs+=("compsize")
    [[ "${XDG_SESSION_TYPE:-wayland}" == "x11" ]] && cli_pkgs+=("xclip")

    run_sudo dnf install -y --skip-unavailable "${cli_pkgs[@]}"

    step_complete "Core CLI utilities installed"
}

