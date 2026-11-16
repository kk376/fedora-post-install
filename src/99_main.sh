# ==============================================================================
# Installation Summary
# ==============================================================================
show_summary() {
    local end_time duration mins secs
    end_time=$(date +%s)
    duration=$((end_time - START_TIME))
    mins=$((duration / 60))
    secs=$((duration % 60))

    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}         INSTALLATION SUMMARY           ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "Duration: ${mins}m ${secs}s | Profile: $PROFILE"
    echo "Steps:    ${COMPLETED_STEPS} completed, ${FAILED_STEPS} failed, ${SKIPPED_STEPS} skipped (of ${TOTAL_STEPS})"
    echo "Shell:    $(get_login_shell)"
    echo "Log file: $LOG_FILE"
    [[ -d "$BACKUP_DIR" ]] && echo "Backups:  $BACKUP_DIR"
    echo ""
    info "Next Steps:"
    echo "  1. Reboot your system to apply kernel modules and group memberships (docker, libvirt)."
    echo "  2. Open your terminal to start using $(get_login_shell)."
}

# ==============================================================================
# Main Execution Orchestrator
# ==============================================================================
main() {
    parse_args "$@"

    if [[ -f /run/ostree-booted ]]; then
        error "Fedora Atomic Desktop detected (/run/ostree-booted is present)."
        info "This script uses traditional DNF package management and is not designed for rpm-ostree systems."
        info "For Silverblue / Kinoite / Bazzite, please use rpm-ostree or containerized workflows."
        exit 1
    fi

    detect_hardware

    # Tee stdout/stderr to log file while keeping /dev/tty interactive for prompts
    exec > >(tee -a "$LOG_FILE") 2>&1

    if $DRY_RUN; then
        echo -e "${MAGENTA}========================================${NC}"
        echo -e "${MAGENTA}   DRY-RUN MODE - No changes will be made${NC}"
        echo -e "${MAGENTA}========================================${NC}"
    fi

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Fedora 44 Post-Install Setup v${SCRIPT_VERSION}${NC}"
    echo -e "${GREEN}========================================${NC}"
    info "Architecture: $SYS_ARCH | Chassis: $CHASSIS_TYPE"
    info "GPUs detected: NVIDIA=$HAS_NVIDIA, AMD=$HAS_AMD, Intel=$HAS_INTEL"

    if [[ "$SYS_ARCH" != "x86_64" && "$SYS_ARCH" != "aarch64" ]]; then
        warn "Untested CPU architecture: $SYS_ARCH"
        confirm "Continue anyway?" "N" || exit 1
    fi

    select_profile_menu

    if ! $DRY_RUN; then
        sudo -v || { error "Sudo privileges are required."; exit 1; }
        while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
        SUDO_PID=$!
    fi

    if ! $UNATTENDED; then
        confirm "Show currently installed package versions?" "N" && show_versions
        if confirm "Restore configuration files from a previous backup?" "N"; then
            restore_backups || true
            return 0
        fi
    fi

    if ! $DRY_RUN && ! check_network; then
        error "No active internet connection detected. Exiting."
        exit 1
    fi

    if ! $DRY_RUN; then
        check_disk_space 20 "$HOME"
    fi

    # Master ordered step registry
    local steps=(
        "setup_dnf:DNF5 & Repositories"
        "setup_dns:DNS Resolvers"
        "setup_cli_core:Core CLI Utilities"
        "setup_shell:Shell & Terminal"
        "setup_fonts:System & Nerd Fonts"
        "setup_multimedia:Multimedia & Audio Codecs"
        "setup_gnome:GNOME Desktop & Extensions"
        "setup_desktop_apps:Desktop Applications"
        "setup_power:Power & Sleep Management"
        "setup_dev:Development Toolchains"
        "setup_editor:Code Editor"
        "setup_docker:Docker & Compose"
        "setup_kvm:KVM/QEMU Virtualization"
        "setup_gaming:Gaming Stack"
        "setup_creator:Creator & Streaming Suite"
        "setup_pre_driver_reboot:Pre-Driver Kernel Checkpoint"
        "setup_drivers:GPU Drivers"
    )

    # True layered profile definitions
    local base_minimal="setup_dnf setup_dns setup_cli_core setup_shell"
    local base_workstation="$base_minimal setup_fonts setup_multimedia setup_gnome setup_desktop_apps setup_power setup_pre_driver_reboot setup_drivers"

    local -A PROFILE_STEPS
    PROFILE_STEPS[minimal]="$base_minimal"
    PROFILE_STEPS[workstation]="$base_workstation"
    PROFILE_STEPS[dev]="$base_workstation setup_dev setup_editor setup_docker setup_kvm"
    PROFILE_STEPS[gaming]="$base_workstation setup_gaming"
    PROFILE_STEPS[creator]="$base_workstation setup_creator"
    PROFILE_STEPS[full]="" # Empty string runs all steps in master registry order

    init_state

    local filtered_steps=()
    for step in "${steps[@]}"; do
        IFS=':' read -r func _ <<< "$step"
        if [[ -z "${PROFILE_STEPS[$PROFILE]}" ]] || [[ " ${PROFILE_STEPS[$PROFILE]} " == *" $func "* ]]; then
            filtered_steps+=("$step")
        fi
    done
    TOTAL_STEPS=${#filtered_steps[@]}

    info "Executing profile '$PROFILE' ($TOTAL_STEPS steps)..."

    for step in "${filtered_steps[@]}"; do
        IFS=':' read -r func name <<< "$step"
        ((++CURRENT_STEP))

        if is_step_completed "$func" && ! $FORCE_RERUN; then
            info "[${CURRENT_STEP}/${TOTAL_STEPS}] Already completed: $name (use --force to re-run)"
            ((++COMPLETED_STEPS))
            continue
        fi

        echo ""
        echo -e "${BLUE}Step: $name${NC}"
        local step_status=0
        (
            set -eo pipefail
            "$func"
        ) || step_status=$?

        if [[ $step_status -eq 100 ]]; then
            info "Reboot initiated by step '$name'. Exiting setup."
            exit 0
        elif [[ $step_status -eq 0 ]]; then
            $DRY_RUN || mark_step_completed "$func"
            ((++COMPLETED_STEPS))
        else
            warn "Step '$name' exited with status $step_status"
            ((++FAILED_STEPS))
        fi
    done

    show_summary
}

cleanup() {
    if [[ -n "${SUDO_PID:-}" ]]; then
        kill "$SUDO_PID" 2>/dev/null || true
    fi
    rm -f /tmp/starship-install-*.sh /tmp/zed-install-*.sh /tmp/agy-install-*.sh 2>/dev/null || true
    rm -rf /tmp/cambria-extract-* 2>/dev/null || true
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    trap 'echo -e "\n${RED}Interrupted by user${NC}"; cleanup; exit 1' INT TERM
    trap cleanup EXIT
    main "$@"
fi
