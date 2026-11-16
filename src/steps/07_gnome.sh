# ==============================================================================
# Step 7: GNOME Desktop Tweaks & Extensions
# ==============================================================================
setup_gnome() {
    log "Configuring GNOME Tweaks, GSConnect & Mutter optimizations..."

    # Check for GNOME desktop environment before applying shell extensions
    local is_gnome=false
    if [[ "${XDG_CURRENT_DESKTOP:-}" =~ GNOME ]] || [[ "${DESKTOP_SESSION:-}" =~ gnome ]] || command -v gnome-shell &>/dev/null || $DRY_RUN; then
        is_gnome=true
    fi

    if ! $is_gnome; then
        info "Non-GNOME desktop detected (${XDG_CURRENT_DESKTOP:-none}) - skipping GNOME shell extensions & Mutter tweaks."
        step_complete "GNOME desktop configured (bypassed for non-GNOME desktop)"
        return 0
    fi

    run_sudo dnf install -y gnome-tweaks gnome-shell-extension-gsconnect gnome-shell-extension-appindicator

    if command -v firewall-cmd &>/dev/null && ! $DRY_RUN; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            run_sudo firewall-cmd --permanent --add-service=kdeconnect 2>/dev/null || true
            run_sudo firewall-cmd --reload 2>/dev/null || true
            success "Firewall port opened for GSConnect / KDE Connect"
        fi
    fi

    if confirm "Apply transparent GTK3/GTK4 titlebar CSS?" "N"; then
        if ! $DRY_RUN; then
            mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
            backup_file "$HOME/.config/gtk-3.0/gtk.css"
            backup_file "$HOME/.config/gtk-4.0/gtk.css"
            cat << 'GTK_CSS' > "$HOME/.config/gtk-3.0/gtk.css"
/* Transparent Headerbar / Titlebar for libdecor & CSD Windows */
window.libdecor-frame,
window.libdecor-frame headerbar,
headerbar.default-decoration,
headerbar.titlebar,
.titlebar,
headerbar {
    background: transparent;
    background-color: transparent;
    border: none;
    box-shadow: none;
}

headerbar button.titlebutton {
    background: rgba(255, 255, 255, 0.08);
    border-radius: 9999px;
    margin: 4px 2px;
}

headerbar button.titlebutton:hover {
    background: rgba(255, 255, 255, 0.22);
}
GTK_CSS
            cp "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"
            success "Transparent headerbar CSS deployed (previous files backed up)"
        else
            dry "Backup and deploy ~/.config/gtk-3.0/gtk.css and ~/.config/gtk-4.0/gtk.css"
        fi
    fi

    if command -v gsettings &>/dev/null && ! $DRY_RUN; then
        gsettings set org.gnome.mutter check-alive-timeout 0 2>/dev/null || true
        gsettings set org.gnome.desktop.interface clock-show-weekday true 2>/dev/null || true
        gsettings set org.gnome.desktop.interface clock-show-seconds true 2>/dev/null || true
        gsettings set org.gnome.shell disable-extension-version-validation true 2>/dev/null || true
        success "GNOME Mutter and interface preferences applied"
    fi

    step_complete "GNOME desktop configured"
}

