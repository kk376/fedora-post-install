# ==============================================================================
# CLI Argument Parsing
# ==============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            --yes|-y|--unattended)
                UNATTENDED=true
                shift
                ;;
            --profile=*)
                PROFILE="${1#*=}"
                PROFILE_SPECIFIED=true
                shift
                ;;
            --profile)
                if [[ $# -lt 2 ]]; then
                    error "Option --profile requires an argument."
                    exit 1
                fi
                PROFILE="$2"
                PROFILE_SPECIFIED=true
                shift 2
                ;;
            --dev-type=*)
                DEV_TYPE="${1#*=}"
                DEV_TYPE_SPECIFIED=true
                shift
                ;;
            --dev-type)
                if [[ $# -lt 2 ]]; then
                    error "Option --dev-type requires an argument."
                    exit 1
                fi
                DEV_TYPE="$2"
                DEV_TYPE_SPECIFIED=true
                shift 2
                ;;
            --force|-f)
                FORCE_RERUN=true
                shift
                ;;
            --help|-h)
                cat <<EOF
Fedora 44 Post-Install Setup Script v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

Options:
  --dry-run, -n         Preview changes without executing
  --yes, -y             Unattended mode (auto-accept safe defaults)
  --profile=PROFILE     Choose setup profile (interactive menu if omitted):
                          minimal     - DNF, DNS, core CLI utilities, shell & terminal
                          workstation - Minimal + fonts, codecs, GNOME, desktop apps, power, drivers (default)
                          dev         - Workstation + dev toolchains, editors, Docker, KVM/QEMU
                          gaming      - Workstation + Steam, Heroic, MangoHud, GameMode
                          creator     - Workstation + OBS Studio, v4l2loopback, wf-recorder, NV Broadcast
                          full        - Complete suite: Workstation + Dev + Gaming + Creator
  --dev-type=GENRE      Choose developer genre for dev/full profile (comma-separated):
                          systems     - C, C++, Rust, CMake, Meson, GDB, Valgrind, ccache
                          web         - Node.js, Corepack (PNPM/Yarn), Python 3, jq
                          android     - ADB, Fastboot, Scrcpy, OpenJDK, Maven, Android Studio
                          ai          - Python Devel, Ruff, UV, GPU Compute (CUDA / ROCm / Intel Compute)
                          all         - Full development suite (default)
  --force, -f           Re-run already completed steps
  --help, -h            Show this help message
EOF
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if $PROFILE_SPECIFIED; then
        case "$PROFILE" in
            minimal|workstation|dev|gaming|creator|full) ;;
            *) error "Unknown profile: $PROFILE (use minimal, workstation, dev, gaming, creator, or full)"; exit 1 ;;
        esac
    fi

    if [[ -n "${DEV_TYPE:-}" && "$DEV_TYPE" != "all" ]]; then
        IFS=',' read -ra genres <<< "$DEV_TYPE"
        for g in "${genres[@]}"; do
            case "$g" in
                systems|web|android|ai) ;;
                *) error "Unknown dev type: $g (use systems, web, android, ai, or all)"; exit 1 ;;
            esac
        done
    fi
}

