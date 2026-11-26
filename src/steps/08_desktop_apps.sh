# ==============================================================================
# Step 8: Desktop Applications (Browser, Media, Flatpaks, Productivity)
# ==============================================================================
setup_desktop_apps() {
    log "Installing Brave Browser & desktop productivity applications..."

    run_sudo dnf install -y --skip-unavailable dnf5-plugins dnf-plugins-core 2>/dev/null || true
    run_sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo --overwrite 2>/dev/null || warn "Failed to add Brave repository"
    local desktop_pkgs=(
        brave-browser vlc qbittorrent telegram-desktop timeshift gparted ntfs-3g
    )
    [[ "${XDG_SESSION_TYPE:-wayland}" == "x11" ]] && desktop_pkgs+=("wmctrl")
    run_sudo dnf install -y --skip-unavailable "${desktop_pkgs[@]}"

    log "Installing essential Flatpaks (LocalSend, Extension Manager)..."
    run flatpak install -y flathub org.localsend.localsend_app com.mattjakeman.ExtensionManager 2>/dev/null || warn "Flatpak installation had warnings"

    # Yazi Terminal File Manager (COPR)
    if confirm "Install Yazi terminal file manager?" "Y"; then
        if run_sudo dnf copr enable -y lihaohong/yazi; then
            run_sudo dnf install -y --skip-unavailable yazi file poppler-utils resvg ImageMagick || warn "Yazi install had warnings"
        fi
    fi

    # Vesktop (Architecture-aware download: upstream uses x86_64 or arm64 on ARM64)
    if confirm "Install Vesktop Discord client?" "Y"; then
        if ! $DRY_RUN; then
            init_run_tmp_dir
            local vesktop_arch="${SYS_ARCH}"
            [[ "${SYS_ARCH}" == "aarch64" ]] && vesktop_arch="arm64"
            local fallback_url="https://github.com/Vencord/Vesktop/releases/latest/download/vesktop.${vesktop_arch}.rpm"
            local vesktop_rpm="$RUN_TMP_DIR/vesktop.rpm"
            rm -f "$vesktop_rpm"
            if github_download "Vencord/Vesktop" "vesktop.*\.(${SYS_ARCH}|arm64)\.rpm" "$vesktop_rpm" "$fallback_url"; then
                run_sudo dnf install -y "$vesktop_rpm" 2>/dev/null || warn "Vesktop RPM install failed"
                rm -f "$vesktop_rpm"
            else
                warn "Could not download Vesktop RPM for $SYS_ARCH"
            fi
        else
            dry "Download and install Vesktop RPM ($SYS_ARCH)"
        fi
    fi

    # Stirling-PDF
    if ! command -v stirling-pdf &>/dev/null && ! rpm -q stirling-pdf &>/dev/null; then
        if confirm "Install Stirling-PDF desktop toolkit?" "N"; then
            if ! $DRY_RUN; then
                if [[ "$SYS_ARCH" != "x86_64" ]]; then
                    warn "Stirling-PDF RPM packages are exclusive to x86_64 (current arch: $SYS_ARCH)"
                else
                    init_run_tmp_dir
                    local stirling_rpm="$RUN_TMP_DIR/stirling-pdf.rpm"
                    rm -f "$stirling_rpm"
                    if github_download "Stirling-Tools/Stirling-PDF" "Stirling-PDF-linux-${SYS_ARCH}\.rpm" "$stirling_rpm" \
                        "https://files.stirlingpdf.com/linux-installer.rpm"; then
                        run_sudo dnf install -y "$stirling_rpm" 2>/dev/null || warn "Stirling-PDF install failed"
                        rm -f "$stirling_rpm"
                    else
                        warn "Could not download Stirling-PDF RPM"
                    fi
                fi
            else
                dry "Download and install Stirling-PDF RPM"
            fi
        fi
    fi

    step_complete "Desktop applications installed"
}

