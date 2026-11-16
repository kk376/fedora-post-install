# ==============================================================================
# Step 1: DNF Configuration & Core Repositories
# ==============================================================================
setup_dnf() {
    log "Configuring DNF5 & Third-Party Repositories..."

    backup_file "/etc/dnf/dnf.conf"

    if ! $DRY_RUN; then
        run_sudo sed -i '/^# BEGIN fedora-setup$/,/^# END fedora-setup$/d' /etc/dnf/dnf.conf
        run_sudo tee -a /etc/dnf/dnf.conf > /dev/null <<'EOF'
# BEGIN fedora-setup
max_parallel_downloads=10
max_downloads_per_mirror=10
defaultyes=True
# END fedora-setup
EOF
    else
        dry "Add max_parallel_downloads=10, max_downloads_per_mirror=10, and defaultyes=True block to /etc/dnf/dnf.conf"
    fi

    log "Enabling RPM Fusion (Free & Nonfree) and Flathub..."
    local fedora_ver
    fedora_ver=$(rpm -E %fedora 2>/dev/null || echo "")
    if [[ -z "$fedora_ver" || "$fedora_ver" == "%fedora" ]]; then
        fedora_ver=$(. /etc/os-release 2>/dev/null && echo "$VERSION_ID" || echo "45")
    fi
    fedora_ver="${fedora_ver:-45}"

    run_sudo dnf install -y --setopt=best=True \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
    run_sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 2>/dev/null || true
    run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || warn "Flathub already configured or failed"

    run_sudo dnf upgrade -y --refresh --setopt=best=True

    if confirm "Configure sudo password feedback (display asterisks)?" "N"; then
        log "Configuring sudo password feedback (asterisks)..."
        if ! $DRY_RUN; then
            run_sudo mkdir -p /etc/sudoers.d
            run_sudo tee /etc/sudoers.d/pwfeedback > /dev/null <<'EOF'
Defaults pwfeedback
EOF
            run_sudo chmod 0440 /etc/sudoers.d/pwfeedback
            if ! run_sudo visudo -c -f /etc/sudoers.d/pwfeedback >/dev/null 2>&1; then
                run_sudo rm -f /etc/sudoers.d/pwfeedback
                warn "Failed to validate sudoers syntax; removed /etc/sudoers.d/pwfeedback"
            else
                success "Sudo password feedback configured (/etc/sudoers.d/pwfeedback)"
            fi
        else
            dry "Configure sudo pwfeedback in /etc/sudoers.d/pwfeedback"
        fi
    fi

    step_complete "DNF & repositories configured"
}

