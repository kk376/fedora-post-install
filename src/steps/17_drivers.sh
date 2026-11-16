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
        log "AMD GPU detected: Installing Freeworld Mesa VA-API & VDPAU drivers..."
        run_sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing 2>/dev/null || \
            run_sudo dnf install -y mesa-va-drivers-freeworld --allowerasing 2>/dev/null || warn "mesa-va-drivers-freeworld swap skipped"
        run_sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing 2>/dev/null || true
    fi

    if $HAS_NVIDIA; then
        log "NVIDIA GPU detected: Installing akmod-nvidia, CUDA & VA-API bridge..."
        run_sudo dnf install -y --skip-unavailable \
            kmodtool akmods mokutil openssl nvtop akmod-nvidia \
            kernel-devel-matched xorg-x11-drv-nvidia-cuda libva-nvidia-driver

        log "Building NVIDIA kernel modules via akmods..."
        run_sudo akmods --force

        # Hybrid graphics optimization ONLY on laptops with both an iGPU (AMD/Intel) and an NVIDIA dGPU
        if $IS_LAPTOP && { $HAS_AMD || $HAS_INTEL; }; then
            local vulkan_conf="/etc/environment.d/10-vulkan-hybrid.conf"
            local selected_driver=""
            $HAS_AMD && selected_driver="*radeon*"
            [[ -z "$selected_driver" ]] && $HAS_INTEL && selected_driver="*intel*"

            if [[ -n "$selected_driver" ]]; then
                log "Hybrid Optimus laptop detected: iGPU power optimization available ($selected_driver + NVIDIA)."
                info "Note: Forcing iGPU Vulkan priority saves battery, but prevents discrete NVIDIA GPU Vulkan offload."
                if confirm "Set $selected_driver as primary Vulkan device for battery savings? (Warning: limits discrete GPU Vulkan offload)" "N"; then
                    if ! $DRY_RUN; then
                        run_sudo mkdir -p /etc/environment.d
                        run_sudo tee "$vulkan_conf" > /dev/null <<EOF
# Prevent desktop apps from waking the discrete NVIDIA GPU unnecessarily
# WARNING: This disables discrete NVIDIA GPU Vulkan offload unless overridden per-command.
VK_LOADER_DRIVERS_SELECT=$selected_driver
EOF
                        success "Hybrid Vulkan priority set to $selected_driver ($vulkan_conf)"
                    else
                        dry "Set VK_LOADER_DRIVERS_SELECT=$selected_driver in $vulkan_conf"
                    fi
                else
                    if [[ -f "$vulkan_conf" ]] && ! $DRY_RUN; then
                        run_sudo rm -f "$vulkan_conf"
                    fi
                    info "Preserving standard Vulkan device discovery for discrete GPU offload and external monitors"
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

