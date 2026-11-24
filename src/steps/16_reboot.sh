# ==============================================================================
# Step 16: Pre-Driver Reboot Checkpoint
# ==============================================================================
setup_pre_driver_reboot() {
    log "Checking running kernel against latest installed kernel-core..."

    if $DRY_RUN; then
        dry "Compare uname -r against latest installed kernel-core RPM"
        step_complete "Reboot checkpoint (dry-run)"
        return 0
    fi

    local running_kernel installed_kernel
    running_kernel=$(uname -r)
    installed_kernel=$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n1 || true)

    if [[ -n "$installed_kernel" && "$running_kernel" != "$installed_kernel" ]]; then
        warn "Kernel update detected:"
        info "  Running kernel:   $running_kernel"
        info "  Installed kernel: $installed_kernel"
        echo ""
        info "Rebooting before building GPU kernel modules ensures akmods targets the new kernel."
        info "Re-run this script after rebooting - it will resume automatically at the GPU Drivers step."
        if confirm "Reboot now?" "Y"; then
            mark_step_completed "setup_pre_driver_reboot"
            step_complete "Reboot checkpoint (rebooting)"
            run_sudo systemctl reboot
            exit 100
        else
            warn "Continuing without reboot; akmods will build for the target kernel."
        fi
    else
        info "Running kernel ($running_kernel) is up to date."
    fi

    step_complete "Kernel checkpoint verified"
}

