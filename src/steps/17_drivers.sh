# ==============================================================================
# Step 17: Multi-Vendor GPU Drivers (Intel, AMD, NVIDIA)
# ==============================================================================
setup_drivers() {
    log "Configuring GPU hardware acceleration drivers..."

    if $HAS_INTEL; then
        log "Intel GPU detected: Installing VA-API media drivers..."
        run_sudo dnf install -y --skip-unavailable intel-media-driver libva-intel-driver 2>/dev/null || true
    fi

    if $HAS_AMD; then
        log "AMD GPU detected: Installing Freeworld Mesa VA-API & Vulkan Video drivers..."
        run_sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing 2>/dev/null || \
            run_sudo dnf install -y mesa-va-drivers-freeworld --allowerasing 2>/dev/null || warn "mesa-va-drivers-freeworld swap skipped"
        run_sudo dnf swap -y mesa-vulkan-drivers mesa-vulkan-drivers-freeworld --allowerasing 2>/dev/null || \
            run_sudo dnf install -y mesa-vulkan-drivers-freeworld --allowerasing 2>/dev/null || warn "mesa-vulkan-drivers-freeworld swap skipped"
    fi

    if $HAS_NVIDIA; then
        log "NVIDIA GPU detected: Installing akmod-nvidia, CUDA, power daemons & VA-API bridge..."
        run_sudo dnf install -y --skip-unavailable \
            kmodtool akmods mokutil openssl nvtop akmod-nvidia \
            kernel-devel-matched xorg-x11-drv-nvidia-cuda libva-nvidia-driver \
            xorg-x11-drv-nvidia-power

        log "Building NVIDIA kernel modules via akmods..."
        run_sudo akmods --force

        log "Enabling NVIDIA power management systemd services..."
        run_sudo systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true

        # Hybrid graphics optimization ONLY on laptops with both an iGPU (AMD/Intel) and an NVIDIA dGPU
        if $IS_LAPTOP && { $HAS_AMD || $HAS_INTEL; }; then
            local hybrid_conf="/etc/environment.d/10-hybrid-graphics.conf"
            local legacy_conf="/etc/environment.d/10-vulkan-hybrid.conf"
            local selected_driver=""
            $HAS_AMD && selected_driver="*radeon*"
            [[ -z "$selected_driver" ]] && $HAS_INTEL && selected_driver="*intel*"

            if [[ -n "$selected_driver" ]]; then
                log "Hybrid Optimus laptop detected: iGPU power optimization available ($selected_driver + NVIDIA)."
                info "Note: Pinning desktop apps to the iGPU allows the discrete NVIDIA GPU to enter D3cold sleep."
                if confirm "Configure iGPU primary offload to allow discrete GPU sleep (D3cold)? (Warning: limits automatic discrete GPU Vulkan offload)" "N"; then
                    if ! $DRY_RUN; then
                        run_sudo mkdir -p /etc/environment.d
                        [[ -f "$legacy_conf" ]] && run_sudo rm -f "$legacy_conf"
                        if $HAS_AMD; then
                            run_sudo tee "$hybrid_conf" > /dev/null <<'EOF'
# Prevent desktop apps from waking the discrete NVIDIA GPU from D3cold sleep
VK_LOADER_DRIVERS_SELECT=*radeon*
LIBVA_DRIVER_NAME=radeonsi
VDPAU_DRIVER=radeonsi
__GLX_VENDOR_LIBRARY_NAME=mesa
EOF
                        elif $HAS_INTEL; then
                            run_sudo tee "$hybrid_conf" > /dev/null <<'EOF'
# Prevent desktop apps from waking the discrete NVIDIA GPU from D3cold sleep
VK_LOADER_DRIVERS_SELECT=*intel*
LIBVA_DRIVER_NAME=iHD
VDPAU_DRIVER=va_gl
__GLX_VENDOR_LIBRARY_NAME=mesa
EOF
                        fi
                        success "Hybrid graphics power priority configured in $hybrid_conf"
                    else
                        dry "Set hybrid iGPU offload environment in $hybrid_conf"
                    fi
                else
                    if ! $DRY_RUN; then
                        [[ -f "$hybrid_conf" ]] && run_sudo rm -f "$hybrid_conf"
                        [[ -f "$legacy_conf" ]] && run_sudo rm -f "$legacy_conf"
                    fi
                    info "Preserving standard GPU device discovery for discrete GPU offload and external monitors"
                fi
            fi
        fi

        if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
            echo ""
            warn "Secure Boot is ENABLED. To sign and load NVIDIA kernel modules:"
            info "  1. sudo kmodgenca -a"
            info "  2. sudo mokutil --import /etc/pki/akmods/certs/public_key.der"
            info "  3. Reboot and enroll the MOK key on the blue UEFI screen."
        fi
    fi

    if ! $HAS_INTEL && ! $HAS_AMD && ! $HAS_NVIDIA; then
        info "No dedicated Intel/AMD/NVIDIA PCIe graphics controller detected."
    fi

    step_complete "GPU drivers configured"
}

