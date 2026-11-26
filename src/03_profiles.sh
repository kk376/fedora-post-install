# ==============================================================================
# State File Functions (Idempotency)
# ==============================================================================
init_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    [[ -f "$STATE_FILE" ]] || touch "$STATE_FILE"
}

is_step_completed() {
    local step="$1"
    [[ -f "$STATE_FILE" ]] && grep -qxF "$step" "$STATE_FILE"
}

mark_step_completed() {
    local step="$1"
    if ! is_step_completed "$step"; then
        echo "$step" >> "$STATE_FILE"
    fi
}

# ==============================================================================
# Interactive Profile Selection & Pre-flight Checks
# ==============================================================================
select_profile_menu() {
    if $PROFILE_SPECIFIED; then
        return 0
    fi

    if $DRY_RUN || $UNATTENDED; then
        PROFILE="workstation"
        info "Auto-selected profile: $PROFILE"
        return 0
    fi

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}         Select Setup Profile           ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "  1) minimal     - DNF, DNS, core CLI utilities, shell & terminal (4 steps)"
    echo "  2) workstation - Minimal + fonts, codecs, GNOME, debloat, desktop apps, power, drivers [default] (12 steps)"
    echo "  3) dev         - Workstation + dev toolchains, editors, Docker, KVM/QEMU (16 steps)"
    echo "  4) gaming      - Workstation + Steam, Heroic, MangoHud, GameMode (13 steps)"
    echo "  5) creator     - Workstation + OBS Studio, v4l2loopback, GStreamer, NV Broadcast (13 steps)"
    echo "  6) full        - Complete suite: Workstation + Dev + Gaming + Creator (18 steps)"
    echo ""

    local choice
    choice=$(prompt_input "Enter choice [1-6, default: 2 (workstation)]: " "2")
    case "$choice" in
        1|minimal)        PROFILE="minimal" ;;
        2|workstation|"") PROFILE="workstation" ;;
        3|dev)            PROFILE="dev" ;;
        4|gaming)         PROFILE="gaming" ;;
        5|creator)        PROFILE="creator" ;;
        6|full)           PROFILE="full" ;;
        *)
            warn "Unrecognized selection '$choice'; defaulting to 'workstation' profile"
            PROFILE="workstation"
            ;;
    esac
    info "Selected profile: $PROFILE"

    if [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]] && ! $DEV_TYPE_SPECIFIED; then
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}         Select Developer Stack         ${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo "  1) systems - C, C++, Rust, CMake, Meson, GDB, Valgrind, ccache"
        echo "  2) web     - Node.js, Corepack (PNPM/Yarn), Python 3, jq"
        echo "  3) android - ADB, Fastboot, Scrcpy, OpenJDK, Maven, Android Studio"
        echo "  4) ai      - Python Devel, Ruff, UV, GPU Compute (CUDA / ROCm / Intel Compute)"
        echo "  5) all     - Full development suite [default]"
        echo ""

        local dev_choice
        dev_choice=$(prompt_input "Select developer genres [1-5 or comma-separated, default: 5 (all)]: " "5")
        case "$dev_choice" in
            1|systems) DEV_TYPE="systems" ;;
            2|web)     DEV_TYPE="web" ;;
            3|android) DEV_TYPE="android" ;;
            4|ai)      DEV_TYPE="ai" ;;
            5|all|"")  DEV_TYPE="all" ;;
            *)
                local translated=()
                IFS=',' read -ra raw_genres <<< "$dev_choice"
                for rg in "${raw_genres[@]}"; do
                    rg="${rg#"${rg%%[![:space:]]*}"}"
                    rg="${rg%"${rg##*[![:space:]]}"}"
                    case "$rg" in
                        1|systems) translated+=("systems") ;;
                        2|web)     translated+=("web") ;;
                        3|android) translated+=("android") ;;
                        4|ai)      translated+=("ai") ;;
                        5|all)     translated+=("all") ;;
                        *) warn "Unknown dev genre '$rg' ignored" ;;
                    esac
                done
                if [[ ${#translated[@]} -gt 0 ]]; then
                    DEV_TYPE=$(IFS=,; echo "${translated[*]}")
                else
                    DEV_TYPE="all"
                fi
                ;;
        esac
        info "Selected dev genres: $DEV_TYPE"
    fi
}

check_network() {
    ping -c 1 -W 2 1.1.1.1 &>/dev/null || \
        ping -c 1 -W 2 8.8.8.8 &>/dev/null || \
        curl -fsSI --proto '=https' --tlsv1.2 --max-time 3 https://fedoraproject.org >/dev/null 2>&1
}

check_disk_space() {
    local required_gb=${1:-20}
    local target_dir=${2:-$HOME}
    local available_gb
    available_gb=$(df -BG "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || true)

    if [[ -z "$available_gb" ]]; then
        warn "Could not determine free disk space for $target_dir - skipping check"
        return 1
    fi

    if (( available_gb < required_gb )); then
        warn "Low disk space: ${available_gb}GB available (${required_gb}GB recommended)"
        if ! confirm "Continue anyway?" "N"; then
            error "Aborting due to low disk space"
            exit 1
        fi
    else
        info "Disk space OK: ${available_gb}GB available"
    fi
}

show_versions() {
    log "Checking installed versions..."
    local packages=("fish" "zsh" "brave-browser" "vesktop" "heroic" "zed" "codium" "agy" "code" "docker" "tlp" "steam" "ffmpeg")
    for pkg in "${packages[@]}"; do
        if rpm -q "$pkg" &>/dev/null; then
            echo "  [OK] $pkg: $(rpm -q --queryformat '%{VERSION}' "$pkg" 2>/dev/null)"
        elif command -v "$pkg" &>/dev/null; then
            echo "  [OK] $pkg: $("$pkg" --version 2>/dev/null | head -1 || echo "installed")"
        elif [[ "$pkg" == "heroic" ]] && flatpak list 2>/dev/null | grep -q "com.heroicgameslauncher.hgl"; then
            echo "  [OK] $pkg: flatpak"
        else
            echo "  [MISSING] $pkg: not installed"
        fi
    done
}

