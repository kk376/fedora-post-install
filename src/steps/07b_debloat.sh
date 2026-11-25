# ==============================================================================
# Step 7b: System & GNOME Debloat Optimization
# ==============================================================================
setup_debloat() {
    log "Configuring system & GNOME debloat optimizations..."

    if $DRY_RUN; then
        dry "Audit and interactively offer debloat tiers (services, clutter apps, RAM hogs, DNF weak deps)"
        step_complete "Debloat optimizations (dry-run)"
        return 0
    fi

    # --------------------------------------------------------------------------
    # Tier 1: Safe Background Service Suppression
    # Disables idle network listeners and unused hardware pollers
    # --------------------------------------------------------------------------
    echo ""
    log "Tier 1: Safe Background Service Suppression"
    info "Disables rygel (UPnP media sharing) and cups-browsed (remote printer broadcasting)."
    info "Note: Local CUPS printing continues to function normally."
    if confirm "Disable unnecessary background service daemons (rygel, cups-browsed)?" "Y"; then
        run_sudo systemctl --global disable rygel.service 2>/dev/null || true
        if ! $DRY_RUN; then
            systemctl --user disable --now rygel.service 2>/dev/null || true
        else
            dry "systemctl --user disable --now rygel.service"
        fi
        run_sudo systemctl disable --now cups-browsed.service 2>/dev/null || true
        success "Disabled rygel and cups-browsed background daemons"
    fi

    if ! compgen -G "/sys/class/wwan*" >/dev/null; then
        if systemctl is-active --quiet ModemManager.service 2>/dev/null; then
            if confirm "No built-in WWAN modem detected (decline if using USB LTE dongles). Disable ModemManager?" "N"; then
                run_sudo systemctl disable --now ModemManager.service 2>/dev/null || true
                success "Disabled ModemManager"
            fi
        fi
    fi

    # --------------------------------------------------------------------------
    # Tier 2: Clutter & Office Applications
    # Removes pre-installed heavy desktop applications and unused utilities
    # --------------------------------------------------------------------------
    echo ""
    log "Tier 2: Desktop Clutter & Pre-installed Applications"
    if rpm -q libreoffice-core &>/dev/null || rpm -qa "libreoffice*" 2>/dev/null | grep -q libreoffice; then
        if confirm "Remove pre-installed LibreOffice suite (~500MB)?" "N"; then
            run_sudo dnf remove -y "libreoffice*" || warn "LibreOffice removal had warnings"
            success "Removed LibreOffice suite"
        fi
    fi

    local stock_apps=(
        gnome-maps
        gnome-weather
        gnome-contacts
        gnome-clocks
        gnome-characters
        gnome-logs
        baobab
        simple-scan
        yelp
        gnome-tour
    )
    local installed_stock=()
    for app in "${stock_apps[@]}"; do
        rpm -q "$app" &>/dev/null && installed_stock+=("$app")
    done

    if [[ ${#installed_stock[@]} -gt 0 ]]; then
        info "Found ${#installed_stock[@]} unused stock GNOME utilities: ${installed_stock[*]}"
        if confirm "Remove unused stock GNOME apps (maps, weather, tour, etc.)?" "N"; then
            run_sudo dnf remove -y "${installed_stock[@]}" || warn "Stock apps removal had warnings"
            success "Removed selected stock GNOME utilities"
        fi
    fi

    # --------------------------------------------------------------------------
    # Tier 3: Extreme RAM Optimization (gnome-software & PackageKit)
    # --------------------------------------------------------------------------
    echo ""
    log "Tier 3: Extreme RAM Optimization (GNOME Software & PackageKit)"
    info "Reclaims 200-400MB idle RAM by removing background update daemons."
    info "Package management will be handled via CLI ('dnf' / 'flatpak') and Extension Manager."
    if confirm "Remove GNOME Software and PackageKit to reclaim 200-400MB idle RAM?" "N"; then
        run_sudo dnf remove -y gnome-software PackageKit PackageKit-command-not-found 2>/dev/null || warn "PackageKit removal had warnings"
        success "Removed gnome-software and PackageKit (idle memory freed)"
    fi

    # --------------------------------------------------------------------------
    # Tier 4: DNF Weak Dependency Prevention
    # --------------------------------------------------------------------------
    echo ""
    log "Tier 4: DNF Weak Dependency Prevention"
    info "Prevents DNF from auto-installing optional 'recommended' packages on future installs."
    if confirm "Set install_weak_deps=False in /etc/dnf/dnf.conf? (May omit optional driver/plugin extras later)" "N"; then
        if ! $DRY_RUN; then
            backup_file "/etc/dnf/dnf.conf"
            if grep -q "^install_weak_deps=" /etc/dnf/dnf.conf 2>/dev/null; then
                run_sudo sed -i 's/^install_weak_deps=.*/install_weak_deps=False/' /etc/dnf/dnf.conf
            else
                echo "install_weak_deps=False" | run_sudo tee -a /etc/dnf/dnf.conf > /dev/null
            fi
            success "Configured install_weak_deps=False in /etc/dnf/dnf.conf"
        else
            dry "Set install_weak_deps=False in /etc/dnf/dnf.conf"
        fi
    fi

    step_complete "Debloat optimizations configured"
}
