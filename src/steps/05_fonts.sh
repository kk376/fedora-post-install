# ==============================================================================
# Step 5: System, Microsoft & Nerd Fonts
# ==============================================================================
setup_fonts() {
    log "Installing system, Microsoft & Nerd fonts..."
    run_sudo dnf install -y --skip-unavailable unzip dejavu-sans-fonts dejavu-serif-fonts \
        dejavu-sans-mono-fonts liberation-sans-fonts liberation-serif-fonts liberation-mono-fonts \
        google-noto-sans-fonts google-noto-serif-fonts google-noto-mono-fonts google-carlito-fonts \
        google-caladea-fonts curl cabextract xorg-x11-font-utils fontconfig

    local msttcore_rpm="/tmp/msttcore-fonts-installer-2.6-1.noarch.rpm"
    local msttcore_hash="55d7f3a86533225634ff3ea2384b4356d9665a29cc7eeacff16602a1714afbb4"
    if run curl -fsSL -o "$msttcore_rpm" "https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm"; then
        if ! $DRY_RUN; then
            if verify_checksum "$msttcore_rpm" "$msttcore_hash"; then
                run_sudo rpm -Uvh --replacepkgs "$msttcore_rpm" 2>/dev/null || warn "msttcore-fonts already installed or failed"
            fi
            rm -f "$msttcore_rpm"
        fi
    fi

    if confirm "Install extended Microsoft office fonts (Cambria, Aptos, Segoe UI)?" "Y"; then
        if ! $DRY_RUN; then
            local ms_fonts_dir="$HOME/.local/share/fonts/ms-fonts"
            mkdir -p "$ms_fonts_dir"

            # 1. Cambria Regular
            if [[ ! -f "$ms_fonts_dir/cambria.ttc" && ! -f "/usr/share/fonts/msttcore/cambria.ttc" ]]; then
                local tmp_cab_dir
                tmp_cab_dir=$(mktemp -d /tmp/cambria-extract-XXXXXX)
                if curl --proto '=https' --tlsv1.2 -fsSL --max-time 60 -o "$tmp_cab_dir/ppv.exe" "https://downloads.sourceforge.net/project/mscorefonts2/cabs/PowerPointViewer.exe"; then
                    if cabextract -q -F ppviewer.cab -d "$tmp_cab_dir" "$tmp_cab_dir/ppv.exe" && \
                       cabextract -q --lowercase -F cambria.ttc -d "$ms_fonts_dir" "$tmp_cab_dir/ppviewer.cab"; then
                        success "Cambria Regular (cambria.ttc) installed"
                    fi
                fi
                rm -rf "$tmp_cab_dir"
            fi

            # 2. Aptos family
            local aptos_base_url="https://raw.githubusercontent.com/XCroatoanX/ttf-aptos/master"
            local aptos_fonts=(
                "aptos.ttf" "aptos-bold.ttf" "aptos-italic.ttf" "aptos-bold-italic.ttf"
                "aptos-light.ttf" "aptos-light-italic.ttf" "aptos-semibold.ttf" "aptos-semibold-italic.ttf"
                "aptos-mono.ttf" "aptos-mono-bold.ttf" "aptos-serif.ttf" "aptos-serif-bold.ttf"
            )
            local aptos_count=0
            for font in "${aptos_fonts[@]}"; do
                if [[ ! -f "$ms_fonts_dir/$font" ]]; then
                    if curl -fsSL --max-time 30 -o "$ms_fonts_dir/$font" "$aptos_base_url/$font"; then
                        ((++aptos_count))
                    fi
                fi
            done
            (( aptos_count > 0 )) && success "Aptos font family installed ($aptos_count fonts)"

            # 3. Segoe UI family
            local segoe_base_url="https://raw.githubusercontent.com/mrbvrz/segoe-ui-linux/master/font"
            local segoe_fonts=("segoeui.ttf" "segoeuib.ttf" "segoeuii.ttf" "segoeuiz.ttf" "seguisb.ttf" "seguisbi.ttf" "seguisym.ttf")
            local segoe_count=0
            for font in "${segoe_fonts[@]}"; do
                if [[ ! -f "$ms_fonts_dir/$font" ]]; then
                    if curl -fsSL --max-time 30 -o "$ms_fonts_dir/$font" "$segoe_base_url/$font"; then
                        ((++segoe_count))
                    fi
                fi
            done
            (( segoe_count > 0 )) && success "Segoe UI font family installed ($segoe_count fonts)"
        else
            dry "Download Cambria, Aptos, and Segoe UI into ~/.local/share/fonts/ms-fonts"
        fi
    fi

    log "Installing FiraCode Nerd Font & Symbols Nerd Font..."
    if ! $DRY_RUN; then
        mkdir -p "$HOME/.local/share/fonts/FiraCode" "$HOME/.local/share/fonts/NerdFonts" "$HOME/.config/fontconfig/conf.d"
        if github_download "ryanoasis/nerd-fonts" "FiraCode\\.zip" "/tmp/FiraCode.zip" \
            "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip"; then
            unzip -oq /tmp/FiraCode.zip -d "$HOME/.local/share/fonts/FiraCode/" && rm -f /tmp/FiraCode.zip
            success "FiraCode Nerd Font installed"
        fi

        if github_download "ryanoasis/nerd-fonts" "NerdFontsSymbolsOnly\\.tar\\.xz" "/tmp/NerdFontsSymbolsOnly.tar.xz" \
            "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.tar.xz"; then
            tar -xf /tmp/NerdFontsSymbolsOnly.tar.xz -C "$HOME/.local/share/fonts/NerdFonts/" 2>/dev/null || true
            tar -xf /tmp/NerdFontsSymbolsOnly.tar.xz -C "$HOME/.config/fontconfig/conf.d/" 10-nerd-font-symbols.conf 2>/dev/null || true
            rm -f /tmp/NerdFontsSymbolsOnly.tar.xz
            success "Symbols Nerd Font installed"
        fi

        fc-cache -fv 2>/dev/null || warn "Failed to update font cache"

        if command -v gsettings &>/dev/null; then
            gsettings set org.gnome.desktop.interface monospace-font-name 'FiraCode Nerd Font 11' 2>/dev/null || true
            gsettings set org.gnome.Ptyxis font-name 'FiraCode Nerd Font 12' 2>/dev/null || true
            gsettings set org.gnome.Ptyxis use-system-font false 2>/dev/null || true
        fi
    else
        dry "Download and extract FiraCode Nerd Font and Symbols Nerd Font"
        dry "fc-cache -fv"
    fi

    step_complete "Fonts installed"
}

