#!/bin/bash
# Fedora 44 Post-Install Setup Script
# Author: Kushagra Kumar
# Version: 5.8.0

# ==============================================================================
# Configuration & Flags
# ==============================================================================
: "${DRY_RUN:=false}"
: "${BACKUP_DIR:=$HOME/.config/fedora-setup-backups/$(date +%Y%m%d_%H%M%S)}"
: "${LOG_FILE:=/tmp/fedora-setup-$(date +%Y%m%d_%H%M%S).log}"
: "${SCRIPT_VERSION:=5.8.0}"
: "${PROFILE:=full}"
: "${DEV_TYPE:=all}"
PROFILE_SPECIFIED=false
DEV_TYPE_SPECIFIED=false
: "${FORCE_RERUN:=false}"
# State checkpoint tracking enables idempotent step skipping and seamless resumption across driver reboots.
: "${STATE_FILE:=$HOME/.config/fedora-setup/state.txt}"
: "${SUDO_PID:=}"

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            --profile=*)
                PROFILE="${1#*=}"
                PROFILE_SPECIFIED=true
                shift
                ;;
            --profile)
                if [[ $# -lt 2 ]]; then
                    echo "Error: Option --profile requires an argument." >&2
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
                    echo "Error: Option --dev-type requires an argument." >&2
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
                echo "Fedora 44 Post-Install Setup Script v${SCRIPT_VERSION}"
                echo ""
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run, -n          Preview changes without executing"
                echo "  --profile=PROFILE      Choose setup profile (if omitted, interactive menu is shown):"
                echo "                           minimal     - DNF, DNS, fonts, shell, browser/codecs"
                echo "                           dev         - Developer stack, Docker, Antigravity, KVM"
                echo "                           gaming      - Multimedia, Steam, Heroic, MangoHud, GameMode, Flatpaks"
                echo "                           workstation - Productive desktop, multimedia, Flatpaks, GPU drivers"
                echo "                           creator     - OBS Studio, v4l2loopback, GStreamer, NV Broadcast"
                echo "                           full        - Complete public suite: Workstation + Dev + Gaming + Creator (default)"
                echo "                           personal    - Author's bespoke workflow: Full + ONLYOFFICE (LibreOffice swap), Postgres 18, ccache, kkfetch, cliamp, ani-cli"
                echo "  --dev-type=GENRE       Choose developer genre for dev profile (comma-separated):"
                echo "                           systems     - C, C++, Rust, CMake, Meson, GDB, Valgrind, Hyperfine"
                echo "                           web         - Node.js, PNPM/Yarn, Python 3, Docker, jq"
                echo "                           android     - ADB, Fastboot, Scrcpy, Java JDK, Android Studio"
                echo "                           ai          - Python 3 Devel, Ruff, CUDA Toolkit with GPU guard"
                echo "                           all         - Full development suite (default)"
                echo "  --force, -f            Re-run completed steps"
                echo "  --help, -h             Show this help message"
                echo ""
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Validate profile if explicitly specified
    if $PROFILE_SPECIFIED; then
        case "$PROFILE" in
            minimal|dev|gaming|workstation|creator|full|personal) ;;
            *) echo "Unknown profile: $PROFILE (use minimal, dev, gaming, workstation, creator, full, or personal)"; exit 1 ;;
        esac
    fi

    # Validate dev genres
    if [[ -n "${DEV_TYPE:-}" && "$DEV_TYPE" != "all" ]]; then
        IFS=',' read -ra genres <<< "$DEV_TYPE"
        for g in "${genres[@]}"; do
            case "$g" in
                systems|web|android|ai) ;;
                *) echo "Unknown dev type: $g (use systems, web, android, ai, or all)"; exit 1 ;;
            esac
        done
    fi
}

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging functions
log() { echo -e "${BLUE}[SETUP]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "\033[0;36m[INFO]${NC} $1"; }
dry() { echo -e "\033[0;35m[DRY-RUN]${NC} Would execute: $1"; }

# Progress tracking
COMPLETED_STEPS=0
FAILED_STEPS=0
SKIPPED_STEPS=0
TOTAL_STEPS=0
START_TIME=$(date +%s)

step_complete() {
    COMPLETED_STEPS=$((COMPLETED_STEPS + 1))
    echo -e "\n${GREEN}[${COMPLETED_STEPS}/${TOTAL_STEPS}]${NC} $1"
}

# ==============================================================================
# Enhanced Helper Functions
# ==============================================================================

# Execute command (or dry-run)
run() {
    if $DRY_RUN; then
        dry "$*"
        return 0
    else
        "$@"
    fi
}

# Execute sudo command (or dry-run)
run_sudo() {
    if $DRY_RUN; then
        dry "sudo $*"
        return 0
    else
        sudo "$@"
    fi
}

is_gaming_profile() {
    [[ "$PROFILE" == "gaming" || "$PROFILE" == "full" || "$PROFILE" == "personal" ]]
}

is_creator_profile() {
    [[ "$PROFILE" == "creator" || "$PROFILE" == "full" || "$PROFILE" == "personal" ]]
}

is_dev_profile() {
    [[ "$PROFILE" == "dev" || "$PROFILE" == "full" || "$PROFILE" == "personal" ]]
}

set_zshrc_line() {
    local pattern="$1" desired="$2"
    grep -qxF "$desired" "$HOME/.zshrc" 2>/dev/null && return 0
    if grep -qE "$pattern" "$HOME/.zshrc" 2>/dev/null; then
        PAT="$pattern" REPL="$desired" awk '
            BEGIN { pat = ENVIRON["PAT"]; repl = ENVIRON["REPL"] }
            $0 ~ pat { print repl; next }
            { print }
        ' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
    fi
    grep -qxF "$desired" "$HOME/.zshrc" 2>/dev/null || echo "$desired" >> "$HOME/.zshrc"
}

verify_checksum() {
    local file="$1" expected="$2"
    local actual
    if [[ ! -f "$file" ]]; then
        error "File not found for checksum verification: $file"
        return 1
    fi
    actual=$(sha256sum "$file" | cut -d' ' -f1)
    if [[ "$actual" != "$expected" ]]; then
        error "Checksum mismatch for $file"
        error "  Expected: $expected"
        error "  Actual:   $actual"
        return 1
    fi
    info "Checksum verified: $file"
    return 0
}

# Download a release asset from GitHub with progressive JSON parser fallback (jq -> python3 -> regex).
# Usage: github_download <owner/repo> <asset_pattern> <output_path> [fallback_url] [expected_sha256]
# asset_pattern is a grep -E regex to match the asset filename.
github_download() {
    local repo="$1" pattern="$2" output="$3" fallback="${4:-}" expected_sha256="${5:-}"
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local download_url=""
    local api_response

    api_response=$(curl -sfL --max-time 10 "$api_url" 2>/dev/null || true)
    if [[ -n "$api_response" ]]; then
        # Primary parser: jq utility
        if command -v jq &>/dev/null; then
            download_url=$(echo "$api_response" | jq -r ".assets[] | select(.name | test(\"$pattern\")) | .browser_download_url" 2>/dev/null | head -1 || true)
        # Secondary fallback: Python 3 json/re standard modules
        elif command -v python3 &>/dev/null; then
            download_url=$(python3 -c "
import sys, json, re
try:
    data = json.loads(sys.stdin.read())
    pat = re.compile(sys.argv[1])
    for a in data.get('assets', []):
        if pat.search(a.get('name', '')):
            print(a.get('browser_download_url', ''))
            break
except Exception:
    pass
" "$pattern" <<< "$api_response" 2>/dev/null || true)
        # Tertiary fallback: Perl-compatible regex via grep
        else
            download_url=$(echo "$api_response" | grep -oP '"browser_download_url":\s*"\K[^"]*' 2>/dev/null | grep -E "$pattern" 2>/dev/null | head -1 || true)
        fi
    fi

    [[ -z "$download_url" ]] && download_url="$fallback"

    if [[ -n "$download_url" ]]; then
        if curl -fL --max-time 120 -o "$output" "$download_url" 2>/dev/null; then
            if [[ -n "$expected_sha256" ]]; then
                if ! verify_checksum "$output" "$expected_sha256"; then
                    rm -f "$output"
                    return 1
                fi
            fi
            return 0
        fi
    fi
    return 1
}

# Backup a file before modifying (preserves directory hierarchy to avoid basename collisions)
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local abs_file
        if [[ "$file" = /* ]]; then
            abs_file="$file"
        else
            abs_file="$(pwd)/$file"
        fi
        local rel_path="${abs_file#/}"
        local backup_path="$BACKUP_DIR/$rel_path"

        if $DRY_RUN; then
            dry "Backup: $file → $backup_path"
            return 0
        fi
        mkdir -p "$(dirname "$backup_path")"
        cp -p "$abs_file" "$backup_path"
        mkdir -p "$BACKUP_DIR"
        echo "$abs_file" >> "$BACKUP_DIR/.manifest"
        sort -u "$BACKUP_DIR/.manifest" -o "$BACKUP_DIR/.manifest"
        info "Backed up: $file → $backup_path"
    fi
}

# Restore system and user configuration files from the most recent backup timestamp.
# Purges STATE_FILE upon restoration to force full step re-evaluation on subsequent runs.
restore_backups() {
    local latest_backup
    # shellcheck disable=SC2012
    latest_backup=$(ls -td ~/.config/fedora-setup-backups/*/ 2>/dev/null | head -1 || true)
    if [[ -z "$latest_backup" ]]; then
        warn "No backups found"
        return 1
    fi
    latest_backup="${latest_backup%/}"

    log "Latest backup: $latest_backup"
    if ! confirm "Restore all files from this backup?" "N"; then
        return 0
    fi

    if [[ -f "$latest_backup/.manifest" ]]; then
        while IFS= read -r orig; do
            [[ -z "$orig" ]] && continue
            local rel_path="${orig#/}"
            local backup_path="$latest_backup/$rel_path"

            if [[ ! -f "$backup_path" ]]; then
                warn "No backup for $orig at $backup_path"
                continue
            fi

            if $DRY_RUN; then
                dry "cp $backup_path $orig"
            elif [[ "$orig" == /etc/* ]]; then
                run_sudo cp "$backup_path" "$orig"
                success "Restored: $orig"
            else
                mkdir -p "$(dirname "$orig")"
                cp "$backup_path" "$orig"
                success "Restored: $orig"
            fi
        done < "$latest_backup/.manifest"
    elif compgen -G "$latest_backup/*/*" >/dev/null; then
        while IFS= read -r -d '' bfile; do
            [[ "$(basename "$bfile")" == ".manifest" ]] && continue
            local rel_path="${bfile#"$latest_backup"/}"
            local orig="/$rel_path"

            if $DRY_RUN; then
                dry "cp $bfile $orig"
            elif [[ "$orig" == /etc/* ]]; then
                run_sudo cp "$bfile" "$orig"
                success "Restored: $orig"
            else
                mkdir -p "$(dirname "$orig")"
                cp "$bfile" "$orig"
                success "Restored: $orig"
            fi
        done < <(find "$latest_backup" -mindepth 2 -type f -print0)
    else
        # Legacy flat backup fallback (.backup files in root of backup dir)
        local originals=(
            "$HOME/.zshrc"
            "$HOME/.bashrc"
            "/etc/dnf/dnf.conf"
            "$HOME/.config/MangoHud/MangoHud.conf"
            "$HOME/.config/starship.toml"
            "$HOME/.config/kitty/kitty.conf"
            "$HOME/.config/ghostty/config.ghostty"
            "$HOME/.config/ghostty/gtk.css"
            "$HOME/.config/alacritty/alacritty.toml"
        )

        for orig in "${originals[@]}"; do
            local name backup_path
            name="$(basename "$orig")"
            backup_path="$latest_backup/$name.backup"

            if [[ ! -f "$backup_path" ]]; then
                continue
            fi

            if $DRY_RUN; then
                dry "cp $backup_path $orig"
            elif [[ "$orig" == /etc/* ]]; then
                run_sudo cp "$backup_path" "$orig"
                success "Restored: $orig"
            else
                cp "$backup_path" "$orig"
                success "Restored: $orig"
            fi
        done
    fi

    if ! $DRY_RUN; then
        rm -f "$STATE_FILE"
        warn "State reset due to restore - all steps will re-run"
    fi
}

# ==============================================================================
# State File Functions (Idempotency)
# ==============================================================================
init_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    [[ -f "$STATE_FILE" ]] || touch "$STATE_FILE"
}

is_step_completed() {
    local step="$1"
    [[ -f "$STATE_FILE" ]] && grep -qx "$step" "$STATE_FILE"
}

mark_step_completed() {
    local step="$1"
    if ! is_step_completed "$step"; then
        echo "$step" >> "$STATE_FILE"
    fi
}

# Confirmation prompt
confirm() {
    local prompt="$1" default="${2:-N}" yn
    if $DRY_RUN; then
        if [[ "$default" == "Y" ]]; then
            dry "Prompt: $prompt (auto-yes in dry-run)"
            return 0
        else
            dry "Prompt: $prompt (auto-no in dry-run)"
            return 1
        fi
    fi
    if [[ "$default" == "Y" ]]; then
        read -p "$prompt (Y/n): " -n 1 -r yn
    else
        read -p "$prompt (y/N): " -n 1 -r yn
    fi
    echo
    if [[ "$default" == "Y" ]]; then
        [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]]
    else
        [[ "$yn" =~ ^[Yy]$ ]]
    fi
}

# Interactive profile selection menu
select_profile_menu() {
    # If profile was explicitly specified via CLI flag, skip interactive menu
    if $PROFILE_SPECIFIED; then
        return 0
    fi

    # In dry-run mode without explicit profile, auto-select full profile
    if $DRY_RUN; then
        dry "Prompt: Select setup profile (auto-full in dry-run)"
        PROFILE="full"
        return 0
    fi

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}       Select Setup Profile             ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "  1) minimal     - DNF, DNS, fonts, shell, browser/codecs (7 steps)"
    echo "  2) workstation - Minimal + power, GNOME, productivity, Flatpaks (11 steps)"
    echo "  3) gaming      - Minimal + power, GNOME, Steam, Heroic, MangoHud, GameMode (11 steps)"
    echo "  4) creator     - Minimal + power, GNOME, OBS Studio, loopback, NV Broadcast (11 steps)"
    echo "  5) dev         - Developer stack, Docker, Antigravity, KVM/QEMU (16 steps)"
    echo "  6) full        - Complete public suite: Workstation + Dev + Gaming + Creator (default) (17 steps)"
    echo "  7) personal    - Author's bespoke workflow: Full + ONLYOFFICE, Postgres, ccache, kkfetch, cliamp, ani-cli (17 steps)"
    echo ""

    local choice=""
    read -r -p "Enter choice [1-7, default: 6 (full)]: " choice || choice=""
    case "$choice" in
        1|minimal) PROFILE="minimal" ;;
        2|workstation) PROFILE="workstation" ;;
        3|gaming) PROFILE="gaming" ;;
        4|creator) PROFILE="creator" ;;
        5|dev) PROFILE="dev" ;;
        6|full|"") PROFILE="full" ;;
        7|personal) PROFILE="personal" ;;
        *)
            warn "Unrecognized selection '$choice'; defaulting to 'full' profile"
            PROFILE="full"
            ;;
    esac
    info "Selected profile: $PROFILE"

    # If dev profile selected and dev genres not specified, prompt for genres
    if [[ "$PROFILE" == "dev" ]] && ! $DEV_TYPE_SPECIFIED; then
        echo ""
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}       Select Developer Stack           ${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo "  1) systems - C, C++, Rust, CMake, Meson, GDB, Valgrind, Hyperfine"
        echo "  2) web     - Node.js, PNPM/Yarn, Python 3, Docker, jq"
        echo "  3) android - ADB, Fastboot, Scrcpy, Java JDK, Android Studio"
        echo "  4) ai      - Python 3 Devel, Ruff, CUDA Toolkit"
        echo "  5) all     - Full development suite (default)"
        echo ""

        local dev_choice=""
        read -r -p "Select developer genres [1-5 or comma-separated, default: 5 (all)]: " dev_choice || dev_choice=""
        case "$dev_choice" in
            1|systems) DEV_TYPE="systems" ;;
            2|web) DEV_TYPE="web" ;;
            3|android) DEV_TYPE="android" ;;
            4|ai) DEV_TYPE="ai" ;;
            5|all|"") DEV_TYPE="all" ;;
            *)
                local translated=()
                IFS=',' read -ra raw_genres <<< "$dev_choice"
                for rg in "${raw_genres[@]}"; do
                    # Strip leading and trailing whitespace
                    rg="${rg#"${rg%%[![:space:]]*}"}"
                    rg="${rg%"${rg##*[![:space:]]}"}"
                    case "$rg" in
                        1|systems) translated+=("systems") ;;
                        2|web) translated+=("web") ;;
                        3|android) translated+=("android") ;;
                        4|ai) translated+=("ai") ;;
                        5|all) translated+=("all") ;;
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

# Network check
check_network() {
    ping -c 1 -W 2 8.8.8.8 &>/dev/null || ping -c 1 -W 2 1.1.1.1 &>/dev/null
}

# Disk space check
check_disk_space() {
    local required_gb=${1:-20}
    local target_dir=${2:-$HOME}
    local available_gb
    available_gb=$(df -BG "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || true)

    if [[ -z "$available_gb" ]]; then
        warn "Could not determine free disk space for $target_dir - skipping check"
        return 0
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

# Show installed versions
show_versions() {
    log "Checking installed versions..."
    local packages=("zsh" "brave-browser" "vesktop" "heroic" "zed" "codium" "agy" "code" "docker" "tlp" "steam" "ffmpeg")
    for pkg in "${packages[@]}"; do
        if rpm -q "$pkg" &>/dev/null; then
            echo "  ✅ $pkg: $(rpm -q --queryformat '%{VERSION}' "$pkg" 2>/dev/null)"
        elif command -v "$pkg" &>/dev/null; then
            echo "  ✅ $pkg: $("$pkg" --version 2>/dev/null | head -1 || echo "installed")"
        elif [[ "$pkg" == "heroic" ]] && flatpak list 2>/dev/null | grep -q "com.heroicgameslauncher.hgl"; then
            echo "  ✅ $pkg: flatpak"
        else
            echo "  ❌ $pkg: not installed"
        fi
    done
}



# ==============================================================================
# DNF Configuration
# ==============================================================================
# Configure DNF package manager parallel fetching, core third-party repositories, and Flathub.
setup_dnf() {
    log "Configuring DNF..."

    backup_file "/etc/dnf/dnf.conf"

    if ! $DRY_RUN; then
        # Prune existing managed block to maintain idempotency across repeated executions
        run_sudo sed -i '/^# BEGIN fedora-setup$/,/^# END fedora-setup$/d' /etc/dnf/dnf.conf

        # max_parallel_downloads=10 saturates broadband pipes during massive multi-package transactions
        # defaultyes=True sets [Y/n] as default confirmation for package transactions
        run_sudo tee -a /etc/dnf/dnf.conf > /dev/null <<EOF
# BEGIN fedora-setup
max_parallel_downloads=10
defaultyes=True
# END fedora-setup
EOF
    else
        dry "Add max_parallel_downloads=10 and defaultyes=True block to dnf.conf (idempotent)"
    fi

    log "Enabling RPM Fusion & Flathub (atomic operation)..."
    # Query RPM %fedora macro to dynamically match host OS release version (fallback to 44)
    local fedora_ver
    fedora_ver=$(rpm -E %fedora 2>/dev/null || echo "44")
    [[ -z "$fedora_ver" || "$fedora_ver" == "%fedora" ]] && fedora_ver="44"
    # --setopt=best=True forces strict highest-version dependency resolution rather than falling back
    run_sudo dnf install -y --setopt=best=True \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
    run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || warn "Flathub already configured or failed"

    run_sudo dnf update -y --refresh --setopt=best=True

    log "Configuring sudo password feedback (asterisks)..."
    if ! $DRY_RUN; then
        run_sudo mkdir -p /etc/sudoers.d
        run_sudo tee /etc/sudoers.d/pwfeedback > /dev/null <<'EOF'
Defaults pwfeedback
EOF
        run_sudo chmod 0440 /etc/sudoers.d/pwfeedback
        success "Sudo password feedback configured (/etc/sudoers.d/pwfeedback)"
    else
        dry "Configure sudo pwfeedback in /etc/sudoers.d/pwfeedback"
    fi

    step_complete "DNF configured"
}

# ==============================================================================
# DNS Configuration
# ==============================================================================
setup_dns() {
    if $DRY_RUN; then
        dry "DNS configuration (interactive step skipped in dry-run)"
        step_complete "DNS (dry-run)"
        return 0
    fi

    echo ""
    log "DNS Configuration"
    echo "Custom DNS replaces your ISP's default DNS with fast, private resolvers."
    echo "Benefits: Faster domain lookups and bypasses ISP-level website blocking/tampering."
    echo "Note: May conflict with internal corporate VPNs or college login portals."
    echo ""
    if ! confirm "Would you like to configure custom DNS?" "Y"; then
        info "Keeping default DHCP/ISP DNS settings"
        step_complete "DNS (skipped)"
        return 0
    fi

    echo "Choose a DNS provider:"
    echo "  1. Cloudflare DNS (1.1.1.1, 1.0.0.1)"
    echo "  2. Google DNS (8.8.8.8, 8.8.4.4)"
    echo "  3. Skip (keep current DNS)"

    local dns_choice DNS_IPV4 DNS_IPV6 DNS_NAME
    read -p "Select [1/2/3] (default: 1): " -n 1 -r dns_choice
    echo ""

    case "$dns_choice" in
        2) DNS_IPV4="8.8.8.8 8.8.4.4"; DNS_IPV6="2001:4860:4860::8888 2001:4860:4860::8844"; DNS_NAME="Google" ;;
        3) info "Keeping current DNS settings"; step_complete "DNS (skipped)"; return 0 ;;
        *) DNS_IPV4="1.1.1.1 1.0.0.1"; DNS_IPV6="2606:4700:4700::1111 2606:4700:4700::1001"; DNS_NAME="Cloudflare" ;;
    esac

    log "Configuring $DNS_NAME DNS..."
    local conns
    conns=$(nmcli -t -f NAME connection show --active 2>/dev/null || true)
    while IFS= read -r conn; do
        [[ -z "$conn" ]] && continue
        # Exclude container bridges, host loopback, and virtual interfaces to avoid breaking container subnet name resolution
        if [[ "$conn" =~ ^(docker|lo|virbr|veth|br-) ]]; then
            info "Skipping virtual interface: $conn"
            continue
        fi
        log "Setting DNS for: $conn"
        nmcli connection modify "$conn" ipv4.ignore-auto-dns yes ipv4.dns "$DNS_IPV4" 2>/dev/null || warn "Failed to set IPv4 DNS for $conn"
        nmcli connection modify "$conn" ipv6.ignore-auto-dns yes ipv6.dns "$DNS_IPV6" 2>/dev/null || warn "Failed to set IPv6 DNS for $conn"
        # Cycle interface connection so systemd-resolved and NetworkManager immediately reload upstream resolvers
        nmcli connection down "$conn" 2>/dev/null || true
        sleep 1
        nmcli connection up "$conn" 2>/dev/null || warn "Failed to restart $conn"
    done <<< "$conns"
    step_complete "$DNS_NAME DNS configured"
}

# ==============================================================================
# Power Management (TLP)
# ==============================================================================
setup_power() {
    warn "⚠️  TLP vs GNOME Power Profiles"
    echo "TLP provides fine-grained power control but:"
    echo "  • Disables GNOME's built-in power profiles UI"
    echo "  • Some AMD laptops work better with power-profiles-daemon"
    echo "  • Fedora upstream now prefers power-profiles-daemon"

    if ! confirm "Use TLP instead of GNOME power profiles?" "N"; then
        info "Keeping GNOME power-profiles-daemon (no changes made)"
        step_complete "Power management (default)"
        return 0
    fi

    # Mask power-profiles-daemon to prevent D-Bus state conflicts with TLP power governor rules
    log "Installing TLP..."
    run_sudo dnf install -y tlp tlp-rdw
    run_sudo systemctl enable tlp.service
    run_sudo systemctl mask power-profiles-daemon.service

    # Apply TLP configuration via oneshot service unit once multi-user.target completes during boot
    run_sudo tee /etc/systemd/system/tlp-autostart.service > /dev/null <<'EOF'
[Unit]
Description=Force TLP apply after boot
After=multi-user.target
Wants=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/tlp start
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    run_sudo systemctl daemon-reload && run_sudo systemctl enable tlp-autostart.service
    run_sudo tlp start
    step_complete "TLP configured"
}

# ==============================================================================
# No-Sleep Settings (GDM & User)
# ==============================================================================
setup_nosleep() {
    log "Disabling auto-sleep..."

    # Configure GDM greeter dconf database: GDM runs under its own system user and dconf profile,
    # requiring isolated configuration in /etc/dconf/db/gdm.d to prevent pre-login display sleep.
    if ! $DRY_RUN; then
        run_sudo mkdir -p /etc/dconf/profile /etc/dconf/db/gdm.d
        if [[ ! -f /etc/dconf/profile/gdm ]]; then
            run_sudo tee /etc/dconf/profile/gdm > /dev/null <<'EOF'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
        fi
        run_sudo tee /etc/dconf/db/gdm.d/01-power > /dev/null <<'EOF'
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-timeout=0
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-timeout=0
sleep-inactive-battery-type='nothing'
EOF
        run_sudo dconf update 2>/dev/null || true
    else
        dry "Create /etc/dconf/db/gdm.d/01-power and run dconf update"
    fi

    # Update active user session settings via gsettings
    local keys=(
        "sleep-inactive-ac-timeout 0"
        "sleep-inactive-ac-type nothing"
        "sleep-inactive-battery-timeout 0"
        "sleep-inactive-battery-type nothing"
    )
    for entry in "${keys[@]}"; do
        local key=${entry%% *} val=${entry#* }
        run gsettings set org.gnome.settings-daemon.plugins.power "$key" "$val" 2>/dev/null || true
    done

    step_complete "No-sleep configured"
}

# ==============================================================================
# Terminal Emulator Selection & Configuration (dev-suite integration)
# ==============================================================================
deploy_terminal_config() {
    local target="$1"
    local dev_suite_local="$HOME/code/dev-suite"
    local dev_suite_raw="https://raw.githubusercontent.com/kk376/dev-suite/main"

    case "$target" in
        ghostty)
            log "Deploying Ghostty configuration from dev-suite..."
            if ! $DRY_RUN; then
                mkdir -p "$HOME/.config/ghostty"
                backup_file "$HOME/.config/ghostty/config.ghostty"
                backup_file "$HOME/.config/ghostty/gtk.css"

                if [[ -d "$dev_suite_local/ghostty" ]]; then
                    cp -f "$dev_suite_local/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"
                    [[ -f "$dev_suite_local/ghostty/gtk.css" ]] && cp -f "$dev_suite_local/ghostty/gtk.css" "$HOME/.config/ghostty/gtk.css"
                else
                    curl -fsSL "$dev_suite_raw/ghostty/config.ghostty" -o "$HOME/.config/ghostty/config.ghostty" 2>/dev/null || warn "Failed to download config.ghostty from dev-suite"
                    curl -fsSL "$dev_suite_raw/ghostty/gtk.css" -o "$HOME/.config/ghostty/gtk.css" 2>/dev/null || true
                fi
                ln -sf "$HOME/.config/ghostty/config.ghostty" "$HOME/.config/ghostty/config"
                success "Ghostty configuration deployed to ~/.config/ghostty/"
            else
                dry "Deploy Ghostty configuration from dev-suite to ~/.config/ghostty/"
            fi
            ;;
        kitty)
            log "Deploying Kitty configuration from dev-suite..."
            if ! $DRY_RUN; then
                mkdir -p "$HOME/.config/kitty"
                backup_file "$HOME/.config/kitty/kitty.conf"

                if [[ -d "$dev_suite_local/kitty" ]]; then
                    cp -f "$dev_suite_local/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
                else
                    curl -fsSL "$dev_suite_raw/kitty/kitty.conf" -o "$HOME/.config/kitty/kitty.conf" 2>/dev/null || warn "Failed to download kitty.conf from dev-suite"
                fi
                success "Kitty configuration deployed to ~/.config/kitty/kitty.conf"
            else
                dry "Deploy Kitty configuration from dev-suite to ~/.config/kitty/kitty.conf"
            fi
            ;;
        alacritty)
            log "Deploying Alacritty configuration from dev-suite..."
            if ! $DRY_RUN; then
                mkdir -p "$HOME/.config/alacritty"
                backup_file "$HOME/.config/alacritty/alacritty.toml"

                if [[ -d "$dev_suite_local/alacritty" ]]; then
                    cp -f "$dev_suite_local/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"
                else
                    curl -fsSL "$dev_suite_raw/alacritty/alacritty.toml" -o "$HOME/.config/alacritty/alacritty.toml" 2>/dev/null || warn "Failed to download alacritty.toml from dev-suite"
                fi
                success "Alacritty configuration deployed to ~/.config/alacritty/alacritty.toml"
            else
                dry "Deploy Alacritty configuration from dev-suite to ~/.config/alacritty/alacritty.toml"
            fi
            ;;
    esac
}

setup_terminal() {
    log "Configuring Terminal Emulator..."

    if [[ "$PROFILE" == "personal" ]]; then
        info "Author profile: Installing Ghostty (author's favorite) with dev-suite configuration..."
        log "Enabling Copr repo scottames/ghostty and installing ghostty..."
        if ! $DRY_RUN; then
            local repo="scottames/ghostty"
            if run_sudo dnf copr enable -y "$repo"; then
                run_sudo dnf install -y --skip-unavailable ghostty || warn "Ghostty package installation failed"
                success "Ghostty installed successfully"
            else
                warn "Failed to enable Copr repository $repo"
            fi
        else
            dry "Enable Copr repo scottames/ghostty and install ghostty via dnf"
        fi
        deploy_terminal_config "ghostty"
        return 0
    fi

    # Dev and Full profiles: interactive choice
    if confirm "Install a modern GPU-accelerated terminal emulator instead of stock Ptyxis?" "Y"; then
        echo ""
        echo -e "${BLUE}Choose your terminal emulator:${NC}"
        echo -e "  ${GREEN}1) Ghostty (Recommended: Fast GPU rendering, native GTK4/Wayland, font ligatures)${NC}"
        echo -e "  2) Kitty (Power-user scripting, Kitty graphics protocol standard)"
        echo -e "  3) Alacritty (Minimalist Rust OpenGL terminal)"
        echo ""

        local term_choice=""
        if $DRY_RUN; then
            term_choice="1"
            dry "Prompt user for Terminal Emulator selection: [1] Ghostty (Recommended), [2] Kitty, [3] Alacritty"
        else
            read -r -p "Enter choice [1-3] (default: 1): " term_choice
            term_choice="${term_choice:-1}"
        fi

        case "$term_choice" in
            1)
                log "Installing Ghostty via Copr (scottames/ghostty)..."
                if ! $DRY_RUN; then
                    local repo="scottames/ghostty"
                    if run_sudo dnf copr enable -y "$repo"; then
                        run_sudo dnf install -y --skip-unavailable ghostty || warn "Ghostty package installation failed"
                        success "Ghostty installed successfully"
                    else
                        warn "Failed to enable Copr repository $repo"
                    fi
                else
                    dry "Enable Copr repo scottames/ghostty and install ghostty via dnf"
                fi

                if confirm "Apply optimized Tokyo Night configuration from dev-suite for Ghostty?" "Y"; then
                    deploy_terminal_config "ghostty"
                fi
                ;;
            2)
                log "Installing Kitty terminal..."
                run_sudo dnf install -y --skip-unavailable kitty

                if confirm "Apply optimized Tokyo Night configuration from dev-suite for Kitty?" "Y"; then
                    deploy_terminal_config "kitty"
                fi
                ;;
            3)
                log "Installing Alacritty terminal..."
                run_sudo dnf install -y --skip-unavailable alacritty

                if confirm "Apply optimized Tokyo Night configuration from dev-suite for Alacritty?" "Y"; then
                    deploy_terminal_config "alacritty"
                fi
                ;;
            *)
                warn "Unrecognized selection '$term_choice'; keeping stock terminal"
                ;;
        esac
    else
        info "Keeping stock Fedora terminal (Ptyxis)"
    fi
}

# ==============================================================================
# ZSH + Starship
# ==============================================================================
setup_shell() {
    log "Installing shell packages (ZSH, Fish)..."
    run_sudo dnf install -y --skip-unavailable zsh fish curl git fontconfig

    if ! $DRY_RUN; then
        mkdir -p "$HOME/.zsh/plugins"

        if [[ ! -d "$HOME/.zsh/plugins/zsh-autosuggestions" ]]; then
            run git clone --depth=1 --branch v0.7.1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/plugins/zsh-autosuggestions" 2>/dev/null || true
        fi
        if [[ ! -d "$HOME/.zsh/plugins/zsh-syntax-highlighting" ]]; then
            run git clone --depth=1 --branch 0.8.0 https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.zsh/plugins/zsh-syntax-highlighting" 2>/dev/null || true
        fi
    fi

    # Shell selection and developer environment configuration
    local selected_shell="skip"
    local selected_shell_name=""
    local enable_dev_shell=false

    if [[ "$PROFILE" == "personal" ]]; then
        info "Author profile: Automatically setting Fish as default shell with developer environment..."
        selected_shell="fish"
        selected_shell_name="Fish"
        enable_dev_shell=true
        if ! $DRY_RUN; then
            if command -v fish &>/dev/null; then
                local fish_bin
                fish_bin=$(command -v fish)
                grep -qxF "$fish_bin" /etc/shells || echo "$fish_bin" | run_sudo tee -a /etc/shells >/dev/null
                run_sudo chsh -s "$fish_bin" "${USER:-$(id -un)}" 2>/dev/null || true
                success "Default shell set to Fish"
            fi
        else
            dry "Set default login shell to Fish for personal profile"
        fi
    elif [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]; then
        echo ""
        info "Default Interactive Shell:"
        info "  1) Fish (Recommended for built-in autosuggestions & syntax highlighting)"
        info "  2) ZSH (with autosuggestions & syntax highlighting)"
        info "  3) Bash"
        info "  4) Skip / Keep current shell (${SHELL:-/bin/bash})"

        local shell_choice=""
        if $DRY_RUN; then
            shell_choice="1"
            dry "Prompt user for default shell selection: [1] Fish (Recommended), [2] ZSH, [3] Bash, [4] Skip (default: 1)"
        else
            read -r -p "Enter choice [1-4] (default: 1): " shell_choice
            shell_choice="${shell_choice:-1}"
        fi

        case "$shell_choice" in
            1)
                selected_shell="fish"
                selected_shell_name="Fish"
                if ! $DRY_RUN; then
                    if command -v fish &>/dev/null; then
                        local fish_bin
                        fish_bin=$(command -v fish)
                        grep -qxF "$fish_bin" /etc/shells || echo "$fish_bin" | run_sudo tee -a /etc/shells >/dev/null
                        run_sudo chsh -s "$fish_bin" "${USER:-$(id -un)}" 2>/dev/null || true
                        success "Default shell set to Fish"
                    fi
                else
                    dry "Set default login shell to Fish via chsh"
                fi
                ;;
            2)
                selected_shell="zsh"
                selected_shell_name="ZSH"
                if ! $DRY_RUN; then
                    if command -v zsh &>/dev/null; then
                        local zsh_bin
                        zsh_bin=$(command -v zsh)
                        grep -qxF "$zsh_bin" /etc/shells || echo "$zsh_bin" | run_sudo tee -a /etc/shells >/dev/null
                        run_sudo chsh -s "$zsh_bin" "${USER:-$(id -un)}" 2>/dev/null || true
                        success "Default shell set to ZSH"
                    fi
                else
                    dry "Set default login shell to ZSH via chsh"
                fi
                ;;
            3)
                selected_shell="bash"
                selected_shell_name="Bash"
                if ! $DRY_RUN; then
                    run_sudo chsh -s /bin/bash "${USER:-$(id -un)}" 2>/dev/null || true
                    success "Default shell set to Bash"
                else
                    dry "Set default login shell to Bash via chsh"
                fi
                ;;
            *)
                selected_shell="skip"
                local current_sh
                current_sh=$(basename "${SHELL:-/bin/bash}")
                selected_shell_name="current shell ($current_sh)"
                info "Keeping current default shell ($current_sh)"
                ;;
        esac

        # Developer-specific environment exports and aliases menu
        echo ""
        info "Developer Environment & Aliases Configuration for $selected_shell_name:"
        info "  1) Developer environment exports & full aliases (Neovim, Git shortcuts, toolchains, pager overrides) [Recommended]"
        info "  2) Clean standard aliases only (clear, ls, cat, less without dev exports)"

        local dev_env_choice=""
        if $DRY_RUN; then
            dev_env_choice="1"
            dry "Prompt for developer environment & aliases configuration for $selected_shell_name: [1] Full developer environment, [2] Clean standard aliases only (default: 1)"
        else
            read -r -p "Enter choice [1-2] (default: 1): " dev_env_choice
            dev_env_choice="${dev_env_choice:-1}"
        fi

        case "$dev_env_choice" in
            1|y|Y|[Yy][Ee][Ss])
                enable_dev_shell=true
                info "Enabling developer environment exports and aliases for $selected_shell_name"
                ;;
            *)
                enable_dev_shell=false
                info "Configuring clean standard aliases only for $selected_shell_name"
                ;;
        esac
    else
        # Minimal, Workstation, Gaming, Creator profiles
        selected_shell="skip"
        enable_dev_shell=false
    fi

    # Determine per-shell developer environment flags
    local fish_dev=false
    local zsh_dev=false
    local bash_dev=false

    if [[ "$PROFILE" == "personal" ]]; then
        fish_dev=true
        zsh_dev=true
        bash_dev=true
    elif $enable_dev_shell; then
        case "$selected_shell" in
            fish)
                fish_dev=true
                ;;
            zsh)
                zsh_dev=true
                ;;
            bash)
                bash_dev=true
                ;;
            skip)
                local cur_sh
                cur_sh=$(basename "${SHELL:-/bin/bash}")
                case "$cur_sh" in
                    fish) fish_dev=true ;;
                    zsh)  zsh_dev=true ;;
                    *)    bash_dev=true ;;
                esac
                ;;
        esac
    fi

    # Starship cross-shell prompt configuration
    local install_starship=false

    if [[ "$PROFILE" == "personal" ]]; then
        info "Author profile: Automatically installing and configuring Starship cross-shell prompt..."
        install_starship=true
    elif [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]; then
        echo ""
        info "Starship Cross-Shell Prompt:"
        info "  * Fast: Written in Rust, asynchronous architecture eliminates perceptible prompt lag."
        info "  * Context-aware: Shows Git branch, staging status, language runtimes (Rust, Python, Node, Go, C), and container context."
        info "  * Cross-shell: Provides an identical Tokyo Night prompt layout and vi-mode indicator across Fish, ZSH, and Bash."
        if confirm "Install and configure Starship prompt?" "Y"; then
            install_starship=true
            info "Enabling Starship prompt configuration"
        else
            install_starship=false
            info "Skipping Starship prompt installation"
        fi
    else
        install_starship=false
    fi

    # Install Starship binary and deploy configuration if enabled
    if $install_starship; then
        if ! command -v starship &>/dev/null && ! $DRY_RUN; then
            if ! run_sudo dnf install -y --skip-unavailable starship 2>/dev/null; then
                log "Installing Starship via official installer..."
                local starship_installer
                starship_installer=$(mktemp /tmp/starship-install-XXXXXX.sh)
                if curl --proto '=https' --tlsv1.2 -fsSL https://starship.rs/install.sh -o "$starship_installer"; then
                    sh "$starship_installer" -y >/dev/null 2>&1 || true
                    rm -f "$starship_installer"
                else
                    warn "Failed to download Starship installer"
                    rm -f "$starship_installer"
                fi
            fi
        fi

        if ! $DRY_RUN; then
            mkdir -p "$HOME/.config"
            backup_file "$HOME/.config/starship.toml"
            cat > "$HOME/.config/starship.toml" <<'STARSHIP_CONFIG'
"$schema" = 'https://starship.rs/config-schema.json'

format = """
╭─ $os\
$username\
$directory\
$git_branch\
$git_status\
$rust\
$python\
$nodejs\
$golang\
$c\
$docker_context\
$cmd_duration\
$time
╰─$character """

[os]
disabled = false
style = "bold blue"
format = "[$symbol]($style) "

[os.symbols]
Windows = " "
Ubuntu = " "
SUSE = " "
Raspbian = " "
Mint = "󰣭 "
Macos = " "
Manjaro = " "
Linux = "󰌽 "
Gentoo = "󰣨 "
Fedora = " "
Alpine = " "
Amazon = " "
Android = " "
Arch = "󰣇 "
Debian = " "
Redhat = "󱄛 "

[username]
show_always = false
style_user = "bold blue"
style_root = "bold red"
format = '[$user]($style) in '

[directory]
style = "bold cyan"
format = "[$path]($style) "
truncation_length = 0
truncate_to_repo = false

[directory.substitutions]
"Documents" = "󰈙 Documents"
"Downloads" = " Downloads"
"Music" = "󰝚 Music"
"Pictures" = " Pictures"
"Developer" = "󰲋 Developer"

[git_branch]
symbol = " "
style = "bold purple"
format = "on [$symbol$branch]($style) "

[git_status]
style = "bold red"
format = '([\[$all_status$ahead_behind\]]($style) )'
conflicted = "󰞇 "
ahead = "⇡${count}"
behind = "⇣${count}"
diverged = "⇕⇡${ahead_count}⇣${behind_count}"
up_to_date = ""
untracked = "?${count}"
stashed = "󰆓 "
modified = "!${count}"
staged = "+${count}"
renamed = "»${count}"
deleted = "✘${count}"

[rust]
symbol = " "
style = "bold red"
format = "via [$symbol($version )]($style) "

[python]
symbol = " "
style = "bold yellow"
format = 'via [${symbol}${pyenv_prefix}(${version} )(\($virtualenv\) )]($style) '

[nodejs]
symbol = " "
style = "bold green"
format = "via [$symbol($version )]($style) "

[golang]
symbol = " "
style = "bold cyan"
format = "via [$symbol($version )]($style) "

[c]
symbol = " "
style = "bold blue"
format = "via [$symbol($version )]($style) "

[docker_context]
symbol = " "
style = "bold blue"
format = "via [$symbol$context]($style) "

[cmd_duration]
min_time = 2_000
show_milliseconds = false
style = "bold yellow"
format = "took [$duration]($style) "

[time]
disabled = false
time_format = "%R"
style = "dimmed white"
format = "at [$time]($style) "

[character]
disabled = false
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
vimcmd_symbol = "[❮](bold green)"
vimcmd_replace_one_symbol = "[❮](bold purple)"
vimcmd_replace_symbol = "[❮](bold purple)"
vimcmd_visual_symbol = "[❮](bold yellow)"
STARSHIP_CONFIG
            success "Starship prompt configuration deployed (~/.config/starship.toml)"
        else
            dry "Deploy Starship prompt configuration to ~/.config/starship.toml"
        fi
    fi

    # Configure ZSH (~/.zshrc)
    if ! $DRY_RUN; then
        backup_file "$HOME/.zshrc"
        if $zsh_dev; then
            log "Configuring developer .zshrc..."
            cat > "$HOME/.zshrc" <<'ZSHRC_DEV'
# ===== Zsh History =====
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

# Ctrl + Left / Right navigation
bindkey '^[[;5D' backward-word
bindkey '^[[;5C' forward-word

bindkey '^L' clear-screen

# ===== Zsh Autosuggestions color =====
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#8a8a8a"

# ===== Zsh plugins (manual) =====
[[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ===== Aliases =====
alias clear='printf "\033[2J\033[3J\033[H"'
alias ls='eza --group-directories-first --classify --icons --git'
alias cat='bat --paging=never --style=plain'
alias less='bat --paging=always --pager="less -R"'
alias la='ls -la'

# --- Git Shortcuts ---
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add -A'
alias gap='git add -p'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gcan='git commit --amend --no-edit'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull --rebase'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate -n 15'
alias glog='git log --oneline --graph --decorate --all'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gsw='git switch'
alias gswc='git switch -c'
alias gst='git stash'
alias gstp='git stash pop'
alias gundo='git reset --soft HEAD~1'

# ===== Environment & PATH =====
export EDITOR=nvim
export VISUAL=nvim
export PAGER=cat
export SYSTEMD_PAGER=cat
export MANPAGER=cat
export BAT_PAGER=""
export DELTA_PAGER=cat
export LESS="-F -X -R"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.opencode/bin:$PATH"
export LIBVIRT_DEFAULT_URI="qemu:///system"
export SUDO_PROMPT="[sudo] 🔒 password for %u: "

# ===== NVM =====
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
ZSHRC_DEV
        else
            log "Configuring standard .zshrc with clean aliases..."
            cat > "$HOME/.zshrc" <<'ZSHRC_CLEAN'
# ===== Zsh History =====
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

# Ctrl + Left / Right navigation
bindkey '^[[;5D' backward-word
bindkey '^[[;5C' forward-word

# ===== Zsh Autosuggestions color =====
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#8a8a8a"

# ===== Zsh plugins (manual) =====
[[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ===== Aliases =====
alias clear='printf "\033[2J\033[3J\033[H"'
alias ls='eza --group-directories-first --classify --icons --git'
alias cat='bat --paging=never --style=plain'
alias less='bat --paging=always --pager="less -R"'
ZSHRC_CLEAN
        fi

        if $install_starship; then
            cat >> "$HOME/.zshrc" <<'ZSHRC_STARSHIP'

# ===== Starship (ALWAYS LAST) =====
eval "$(starship init zsh)"
ZSHRC_STARSHIP
        fi

        if $zsh_dev; then
            success "Developer ZSH configuration deployed (~/.zshrc)"
        else
            success "Clean standard ZSH configuration deployed (~/.zshrc)"
        fi
    else
        if $zsh_dev; then
            dry "Deploy ZSH developer configuration (~/.zshrc)"
        else
            dry "Deploy ZSH clean standard aliases (~/.zshrc)"
        fi
    fi

    # Configure Bash (~/.bashrc)
    if ! $DRY_RUN; then
        backup_file "$HOME/.bashrc"
        if grep -q "FEDORA_POST_INSTALL_MANAGED" "$HOME/.bashrc" 2>/dev/null; then
            sed -i '/# >>> FEDORA_POST_INSTALL_MANAGED >>>/,/# <<< FEDORA_POST_INSTALL_MANAGED <<</d' "$HOME/.bashrc"
        elif grep -q "starship init bash" "$HOME/.bashrc" 2>/dev/null; then
            sed -i '/# ===== Starship/,/starship init bash/d' "$HOME/.bashrc" 2>/dev/null || true
        fi

        if $bash_dev; then
            log "Configuring developer .bashrc..."
            cat >> "$HOME/.bashrc" <<'BASHRC_DEV'

# >>> FEDORA_POST_INSTALL_MANAGED >>>
# ===== Developer Environment & Aliases =====
export EDITOR=nvim
export VISUAL=nvim
export PAGER=cat
export SYSTEMD_PAGER=cat
export MANPAGER=cat
export BAT_PAGER=""
export DELTA_PAGER=cat
export LESS="-F -X -R"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.opencode/bin:$PATH"
export LIBVIRT_DEFAULT_URI="qemu:///system"
export SUDO_PROMPT="[sudo] 🔒 password for %u: "

# ===== Aliases =====
alias clear='printf "\033[2J\033[3J\033[H"'
alias ls='eza --group-directories-first --classify --icons --git'
alias cat='bat --paging=never --style=plain'
alias less='bat --paging=always --pager="less -R"'
alias la='ls -la'

# --- Git Shortcuts ---
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add -A'
alias gap='git add -p'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gcan='git commit --amend --no-edit'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpl='git pull --rebase'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate -n 15'
alias glog='git log --oneline --graph --decorate --all'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gsw='git switch'
alias gswc='git switch -c'
alias gst='git stash'
alias gstp='git stash pop'
alias gundo='git reset --soft HEAD~1'

# ===== NVM =====
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
BASHRC_DEV
        else
            log "Configuring standard .bashrc with clean aliases..."
            cat >> "$HOME/.bashrc" <<'BASHRC_CLEAN'

# >>> FEDORA_POST_INSTALL_MANAGED >>>
# ===== Clean Aliases =====
alias clear='printf "\033[2J\033[3J\033[H"'
alias ls='eza --group-directories-first --classify --icons --git'
alias cat='bat --paging=never --style=plain'
alias less='bat --paging=always --pager="less -R"'
BASHRC_CLEAN
        fi

        if $install_starship; then
            cat >> "$HOME/.bashrc" <<'BASHRC_STARSHIP'

# ===== Starship (ALWAYS LAST) =====
eval "$(starship init bash)"
BASHRC_STARSHIP
        fi

        echo "# <<< FEDORA_POST_INSTALL_MANAGED <<<" >> "$HOME/.bashrc"

        if $bash_dev; then
            success "Developer Bash configuration deployed (~/.bashrc)"
        else
            success "Clean standard Bash configuration deployed (~/.bashrc)"
        fi
    else
        if $bash_dev; then
            dry "Deploy Bash developer configuration (~/.bashrc)"
        else
            dry "Deploy Bash clean standard aliases (~/.bashrc)"
        fi
    fi

    # Configure Fish (~/.config/fish/config.fish)
    if ! $DRY_RUN; then
        mkdir -p "$HOME/.config/fish"
        backup_file "$HOME/.config/fish/config.fish"

        if $fish_dev; then
            log "Configuring developer config.fish..."
            cat > "$HOME/.config/fish/config.fish" <<'FISH_DEV'
# Disable default welcome greeting
set -g fish_greeting ""

# ===== Colors & Styling =====
# Brighter, readable autosuggestion color (matching Tokyo Night palette)
set -g fish_color_autosuggestion 828bb8

# ===== Environment & PATH =====
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx PAGER cat
set -gx SYSTEMD_PAGER cat
set -gx MANPAGER cat
set -gx BAT_PAGER ""
set -gx DELTA_PAGER cat
set -gx LESS "-F -X -R"
set -gx LIBVIRT_DEFAULT_URI "qemu:///system"
set -gx SUDO_PROMPT "[sudo] 🔒 password for %u: "

# Add personal bin paths
fish_add_path -m $HOME/.local/bin $HOME/.cargo/bin $HOME/.opencode/bin

# ===== Aliases =====
alias clear 'printf "\033[2J\033[3J\033[H"'
alias ls 'eza --group-directories-first --classify --icons --git'
alias cat 'bat --paging=never --style=plain'
alias less 'bat --paging=always --pager="less -R"'
alias la 'ls -la'

# --- Git Shortcuts ---
alias gs 'git status -sb'
alias ga 'git add'
alias gaa 'git add -A'
alias gap 'git add -p'
alias gc 'git commit'
alias gcm 'git commit -m'
alias gca 'git commit --amend'
alias gcan 'git commit --amend --no-edit'
alias gp 'git push'
alias gpf 'git push --force-with-lease'
alias gpl 'git pull --rebase'
alias gd 'git diff'
alias gds 'git diff --staged'
alias gl 'git log --oneline --graph --decorate -n 15'
alias glog 'git log --oneline --graph --decorate --all'
alias gco 'git checkout'
alias gcb 'git checkout -b'
alias gsw 'git switch'
alias gswc 'git switch -c'
alias gst 'git stash'
alias gstp 'git stash pop'
alias gundo 'git reset --soft HEAD~1'

# ===== FZF Fuzzy Finder =====
if type -q fzf
    fzf --fish | source
end
FISH_DEV
        else
            log "Configuring standard config.fish with clean aliases..."
            cat > "$HOME/.config/fish/config.fish" <<'FISH_CLEAN'
# Disable default welcome greeting
set -g fish_greeting ""

# ===== Colors & Styling =====
set -g fish_color_autosuggestion 828bb8

# ===== Aliases =====
alias clear 'printf "\033[2J\033[3J\033[H"'
alias ls 'eza --group-directories-first --classify --icons --git'
alias cat 'bat --paging=never --style=plain'
alias less 'bat --paging=always --pager="less -R"'
FISH_CLEAN
        fi

        if $install_starship; then
            cat >> "$HOME/.config/fish/config.fish" <<'FISH_STARSHIP'

# ===== Starship Prompt (ALWAYS LAST) =====
if type -q starship
    starship init fish | source
end
FISH_STARSHIP
        fi

        if $fish_dev; then
            success "Developer Fish configuration deployed (~/.config/fish/config.fish)"
        else
            success "Clean standard Fish configuration deployed (~/.config/fish/config.fish)"
        fi
    else
        if $fish_dev; then
            dry "Deploy Fish developer configuration (~/.config/fish/config.fish)"
        else
            dry "Deploy Fish clean standard aliases (~/.config/fish/config.fish)"
        fi
    fi

    # Terminal emulator configuration (dev, full, and personal profiles only)
    if is_dev_profile; then
        setup_terminal
    fi

    # Option: KKFetch System Information CLI (Created by Kushagra Kumar)
    echo ""
    info "KKFetch (by Kushagra Kumar / kk376, script author):"
    info "  • Ultra-fast, zero-dependency cross-platform system information CLI written in Rust (Linux, macOS, Windows & Android)."
    info "  • Why KKFetch? Sub-millisecond startup, zero-fork kernel probers, RPM MTIME package caching, and vibrant 256-color ANSI distro art with lower memory footprint than Neofetch or Fastfetch."
    if confirm "Install KKFetch system information tool via Copr (kk376/kkfetch)?" "Y"; then
        log "Enabling Copr repo kk376/kkfetch and installing kkfetch..."
        local repo="kk376/kkfetch"
        if run_sudo dnf copr enable -y "$repo"; then
            run_sudo dnf install -y --skip-unavailable kkfetch || warn "kkfetch package installation failed"
            success "KKFetch installed successfully"
        else
            warn "Failed to enable Copr repository $repo"
        fi
    else
        info "Skipping KKFetch installation"
    fi

    step_complete "Shell configured"
}

# ==============================================================================
# Brave Browser + Multimedia
# ==============================================================================
setup_browser_multimedia() {
    log "Installing Brave & multimedia..."

    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        warn "RPM Fusion may not be installed correctly - multimedia packages may fail"
    fi

    run_sudo dnf install -y dnf-plugins-core
    run_sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo --overwrite 2>/dev/null || true
    run_sudo dnf install -y brave-browser mozilla-openh264

    run_sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    run_sudo dnf install -y \
        gstreamer1-plugins-bad-freeworld \
        gstreamer1-plugins-ugly \
        gstreamer1-vaapi \
        mesa-va-drivers-freeworld \
        --allowerasing 2>/dev/null || true
    run_sudo dnf group upgrade -y multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin 2>/dev/null || true
    run_sudo dnf group upgrade -y sound-and-video 2>/dev/null || true

    # System-wide WirePlumber Bluetooth High-Definition Audio (prioritize LDAC, AAC, aptX, SBC-XQ across all user profiles)
    log "Configuring system-wide WirePlumber Bluetooth audio optimization..."
    if ! $DRY_RUN; then
        run_sudo mkdir -p /etc/wireplumber/wireplumber.conf.d
        run_sudo tee /etc/wireplumber/wireplumber.conf.d/50-bluez.conf > /dev/null <<'BLUEZ_CONF'
monitor.bluez.properties = {
  bluez5.roles = [ a2dp_sink a2dp_source hfp_hf hfp_ag ]
  bluez5.codecs = [ ldac aac aptx_hd aptx sbc_xq sbc ]
  bluez5.enable-sbc-xq = true
  bluez5.enable-msbc = true
  bluez5.enable-hw-volume = true
}
BLUEZ_CONF
        success "WirePlumber Bluetooth HD audio configured system-wide"
    else
        dry "Deploy /etc/wireplumber/wireplumber.conf.d/50-bluez.conf"
    fi

    # System-wide PipeWire Dynamic Multi-Rate Bit-Perfect Audio (44.1k to 192k across all user profiles)
    log "Configuring system-wide PipeWire bit-perfect dynamic clock rates..."
    if ! $DRY_RUN; then
        run_sudo mkdir -p /etc/pipewire/pipewire.conf.d
        run_sudo tee /etc/pipewire/pipewire.conf.d/99-clock-rates.conf > /dev/null <<'CLOCK_CONF'
context.properties = {
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]
}
CLOCK_CONF
        if systemctl --user is-active wireplumber &>/dev/null; then
            systemctl --user restart pipewire wireplumber 2>/dev/null || true
        fi
        success "PipeWire dynamic clock rates configured system-wide"
    else
        dry "Deploy /etc/pipewire/pipewire.conf.d/99-clock-rates.conf"
    fi

    step_complete "Browser & multimedia ready"
}

# ==============================================================================
# Pre-Driver Reboot Checkpoint
# ==============================================================================
# Verifies running kernel matches installed kernel RPM before compiling out-of-tree modules.
# Prevents akmods/DKMS builds from targeting mismatched kernel headers or failing dynamically.
setup_pre_driver_reboot() {
    log "Pre-driver reboot checkpoint"

    if $DRY_RUN; then
        dry "Check running kernel vs installed kernel, prompt reboot if mismatched"
        step_complete "Reboot checkpoint (dry-run)"
        return 0
    fi

    local running_kernel installed_kernel
    running_kernel=$(uname -r)
    installed_kernel=$(rpm -q --last kernel-core kernel 2>/dev/null | head -1 | awk '{print $1}' | sed -E 's/kernel-(core-)?//' || true)

    if [[ "$running_kernel" != "$installed_kernel" ]]; then
        warn "Kernel mismatch detected"
        info "  Running:   $running_kernel"
        info "  Installed: $installed_kernel"
        echo ""
        echo "All packages and software have been installed."
        echo "A reboot is needed before driver setup so that kernel modules"
        echo "build against the kernel you're actually going to use."
        echo ""
        echo "After rebooting, re-run this script with the same arguments."
        echo "It will skip everything already done and pick up at GPU drivers."
        echo ""
        if confirm "Reboot now?" "Y"; then
            # Persist completion flag so script resumes at driver configuration upon reboot
            mark_step_completed "setup_pre_driver_reboot"
            step_complete "Reboot checkpoint (rebooting)"
            run_sudo reboot
            exit 0
        else
            warn "Skipping reboot. Driver modules may build against a stale kernel."
            echo "If you run into driver issues after this, reboot and re-run the script."
        fi
    else
        info "Running kernel matches installed kernel — no reboot needed"
    fi

    step_complete "Reboot checkpoint"
}

# ==============================================================================
# Smart Driver Detection
# ==============================================================================
# Probes PCIe subsystem and chassis form-factor to install matching GPU hardware acceleration drivers.
setup_drivers() {
    if [[ "$PROFILE" == "minimal" ]]; then
        if ! confirm "Configure GPU drivers?" "N"; then
            info "Skipping GPU driver setup for minimal profile"
            step_complete "Drivers (skipped)"
            return 0
        fi
    fi

    log "Detecting Hardware..."

    local CHASSIS GPU_NVIDIA GPU_AMD GPU_INTEL
    CHASSIS=$(hostnamectl chassis 2>/dev/null || echo "unknown")
    GPU_NVIDIA=$(lspci | grep -Ei 'VGA|3D|Display' | grep -i nvidia || true)
    GPU_AMD=$(lspci | grep -Ei 'VGA|3D|Display' | grep -i amd || true)
    GPU_INTEL=$(lspci | grep -Ei 'VGA|3D|Display' | grep -i intel || true)

    log "Detected Chassis: $CHASSIS"

    # Install Intel VA-API user-mode media driver for Broadwell (Gen8) and newer GPUs
    if [[ -n "$GPU_INTEL" ]]; then
        log "Intel GPU Detected: Installing intel-media-driver..."
        run_sudo dnf install -y intel-media-driver
    fi

    # Install RPM Fusion freeworld Mesa VA-API driver to unlock patent-encumbered H.264/H.265/VC-1 hardware acceleration
    if [[ -n "$GPU_AMD" ]]; then
        log "AMD GPU Detected: Ensuring freeworld hardware VA-API drivers..."
        run_sudo dnf install -y mesa-va-drivers-freeworld --allowerasing 2>/dev/null || \
            run_sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing 2>/dev/null || true
    fi

    if [[ -n "$GPU_NVIDIA" ]]; then
        log "NVIDIA GPU Detected."

        # Install akmod tooling, NVIDIA drivers, CUDA, v4l2loopback for virtual cameras, and MOK utility
        run_sudo dnf install -y kmodtool akmods mokutil openssl nvtop akmod-nvidia kernel-devel-matched xorg-x11-drv-nvidia-kmodsrc xorg-x11-drv-nvidia-cuda libva-nvidia-driver akmod-v4l2loopback v4l2loopback v4l-utils dkms

        # Force immediate akmod compilation for running kernel
        log "Building NVIDIA kernel modules (this may take a few minutes)..."
        run_sudo akmods --force

        if modinfo nvidia &>/dev/null; then
            success "NVIDIA module built successfully"
        else
            warn "NVIDIA module not yet available - will build during boot"
        fi

        local IS_LAPTOP=false
        if [[ "$CHASSIS" == "laptop" || "$CHASSIS" == "notebook" || "$CHASSIS" == "convertible" || "$CHASSIS" == "portable" ]] || compgen -G "/sys/class/power_supply/BAT*" > /dev/null; then
            IS_LAPTOP=true
        fi

        if $IS_LAPTOP; then
            log "Laptop detected. Checking for Optimus/Hybrid setup..."
            if [[ -n "$GPU_AMD" || -n "$GPU_INTEL" ]]; then
                log "Hybrid Graphics detected: Configuring Vulkan loader to prevent dGPU wake latency..."
                local VULKAN_CONF="/etc/environment.d/10-vulkan-hybrid.conf"
                local SELECTED_DRIVER=""

                if [[ -n "$GPU_AMD" ]]; then
                    SELECTED_DRIVER="*radeon*"
                elif [[ -n "$GPU_INTEL" ]]; then
                    SELECTED_DRIVER="*intel*"
                fi

                if [[ -n "$SELECTED_DRIVER" ]]; then
                    if ! $DRY_RUN; then
                        run_sudo mkdir -p /etc/environment.d
                        run_sudo tee "$VULKAN_CONF" > /dev/null <<EOF
# Prevent Vulkan loader from waking discrete NVIDIA GPU on desktop app launch
VK_LOADER_DRIVERS_SELECT=$SELECTED_DRIVER
EOF
                        if systemctl --user is-system-running &>/dev/null; then
                            systemctl --user set-environment VK_LOADER_DRIVERS_SELECT="$SELECTED_DRIVER" 2>/dev/null || true
                        fi
                        success "Vulkan driver priority set to $SELECTED_DRIVER in $VULKAN_CONF"
                    else
                        dry "Configure Vulkan driver priority ($SELECTED_DRIVER) in $VULKAN_CONF"
                    fi
                fi
            else
                log "Dedicated Nvidia only (MUX Switch or Desktop replacement). Skipping Vulkan driver priority override."
            fi
        fi

        echo ""
        echo "================================================================================"
        echo "                      SECURE BOOT & NVIDIA DRIVER SIGNING                      "
        echo "================================================================================"
        echo "Secure Boot is an EFI firmware security feature required by modern systems."
        echo "Fedora's akmods automatically signs locally built kernel modules with a self-"
        echo "generated key, which must be imported into your EFI firmware (MOK)."
        echo ""
        echo "You DO NOT need to disable Secure Boot or switch to legacy BIOS mode."
        echo ""
        echo "Reference: https://rpmfusion.org/Howto/Secure%20Boot"
        echo "Documentation: /usr/share/doc/akmods/README.secureboot"
        echo ""
        echo "--------------------------------------------------------------------------------"
        echo "1. Securing your key:"
        echo "--------------------------------------------------------------------------------"
        echo "Because the Secure Boot key is stored locally in /etc/pki/akmods, consider"
        echo "encrypting your rootfs (LUKS) to protect the private signing key."
        echo ""
        echo "--------------------------------------------------------------------------------"
        echo "2. Manual Key Generation & MOK Enrollment Steps:"
        echo "--------------------------------------------------------------------------------"
        echo "If you have Secure Boot enabled and wish to sign your drivers:"
        echo ""
        echo "a) Install required tools:"
        echo "   sudo dnf install -y kmodtool akmods mokutil openssl"
        echo ""
        echo "b) Generate a default keypair:"
        echo "   sudo kmodgenca -a"
        echo ""
        echo "c) Import the public key into MOK:"
        echo "   sudo mokutil --import /etc/pki/akmods/certs/public_key.der"
        echo "   -> Enter a temporary password when prompted (you will need this on reboot)."
        echo ""
        echo "d) Reboot your system:"
        echo "   systemctl reboot"
        echo ""
        echo "e) On the blue 'MOK Management' screen after reboot:"
        echo "   - Select 'Enroll MOK'"
        echo "   - Select 'Continue' -> 'Yes'"
        echo "   - Enter the password you set above (⚠️ WARNING: Keyboard is mapped to QWERTY!)"
        echo "   - Select 'Reboot'"
        echo ""
        echo "--------------------------------------------------------------------------------"
        echo "3. BIOS / EFI Firmware Updates:"
        echo "--------------------------------------------------------------------------------"
        echo "When updating the BIOS/UEFI firmware, the enrolled MOK key may be cleared."
        echo "Re-enroll the key anytime with:"
        echo "   sudo mokutil --import /etc/pki/akmods/certs/public_key.der"
        echo "================================================================================"
        echo ""
    else
        log "No NVIDIA GPU found. Skipping proprietary drivers."
    fi

    step_complete "Drivers configured!!"
}

# ==============================================================================
# COPR Packages
# ==============================================================================
setup_copr() {
    log "Installing COPR packages..."
    local coprs=(
        "zeno/scrcpy:scrcpy:Scrcpy - Android Screen Mirroring & Control:Low-latency Android device screen mirroring and control over USB/Wi-Fi without root.:Install if you mirror Android devices or test mobile apps. Otherwise skip."
        "lihaohong/yazi:yazi file ffmpeg 7zip jq poppler-utils fd-find ripgrep fzf zoxide resvg xclip wl-clipboard xsel ImageMagick:Yazi - Terminal File Manager with Rich Previews:Blazing-fast terminal file manager in Rust with async I/O and inline image/video/PDF previews.:Install if you prefer keyboard-driven terminal navigation with rich media previews. Otherwise skip."
        "kk376/kkfetch:kkfetch:kkfetch - Fast System Info Fetch Tool:Lightweight, high-performance system information fetch tool in Rust.:Install if you want a fast, modern system fetch tool in your terminal. Otherwise skip."
    )
    for entry in "${coprs[@]}"; do
        local repo pkgs title desc rec
        repo="${entry%%:*}"
        local rest="${entry#*:}"
        pkgs="${rest%%:*}"
        rest="${rest#*:}"
        title="${rest%%:*}"
        rest="${rest#*:}"
        desc="${rest%%:*}"
        rec="${rest#*:}"

        echo ""
        info "$title (COPR: $repo):"
        info "  • $desc"
        info "  • Recommendation: $rec"
        if confirm "Enable COPR repo '$repo' and install $title?" "Y"; then
            if run_sudo dnf copr enable -y "$repo"; then
                # shellcheck disable=SC2086
                run_sudo dnf install -y --skip-unavailable $pkgs || warn "$pkgs install failed"
            else
                warn "Failed to enable COPR repo $repo"
            fi
        else
            info "Skipping $title installation"
        fi
    done
    step_complete "COPR packages installed"
}

# ==============================================================================
# System Fonts
# ==============================================================================
setup_fonts() {
    log "Installing fonts..."
    run_sudo dnf install -y --skip-unavailable unzip mscore-fonts mscore-fonts-all dejavu-sans-fonts dejavu-serif-fonts \
        dejavu-sans-mono-fonts liberation-sans-fonts liberation-serif-fonts liberation-mono-fonts \
        google-noto-sans-fonts google-noto-serif-fonts google-noto-mono-fonts google-carlito-fonts google-caladea-fonts google-crosextra-caladea-fonts \
        curl cabextract xorg-x11-font-utils fontconfig

    local msttcore_rpm="msttcore-fonts-installer-2.6-1.noarch.rpm"
    local msttcore_hash="55d7f3a86533225634ff3ea2384b4356d9665a29cc7eeacff16602a1714afbb4"
    if run curl -sLO "https://downloads.sourceforge.net/project/mscorefonts2/rpms/$msttcore_rpm"; then
        if $DRY_RUN; then
            dry "verify_checksum $msttcore_rpm $msttcore_hash && sudo rpm -ivh $msttcore_rpm"
        else
            if verify_checksum "$msttcore_rpm" "$msttcore_hash"; then
                run_sudo rpm -ivh "$msttcore_rpm" 2>/dev/null || true
            else
                warn "Failed to verify checksum for $msttcore_rpm, skipping RPM installation"
            fi
            run rm -f "$msttcore_rpm"
        fi
    fi

    log "Installing extended Microsoft fonts (Cambria Regular, Aptos, Segoe UI)..."
    if ! $DRY_RUN; then
        local ms_fonts_dir="$HOME/.local/share/fonts/ms-fonts"
        mkdir -p "$ms_fonts_dir"

        # 1. Cambria Regular (cambria.ttc) from PowerPointViewer cabinet
        if [[ ! -f "$ms_fonts_dir/cambria.ttc" && ! -f "/usr/share/fonts/msttcore/cambria.ttc" ]]; then
            local tmp_cab_dir
            tmp_cab_dir=$(mktemp -d /tmp/cambria-extract-XXXXXX 2>/dev/null || echo "/tmp/cambria-extract-$$")
            if run curl --proto '=https' --tlsv1.2 -fsSL --max-time 60 -o "$tmp_cab_dir/ppv.exe" "https://downloads.sourceforge.net/project/mscorefonts2/cabs/PowerPointViewer.exe"; then
                if run cabextract -q -F ppviewer.cab -d "$tmp_cab_dir" "$tmp_cab_dir/ppv.exe" && \
                   run cabextract -q --lowercase -F cambria.ttc -d "$ms_fonts_dir" "$tmp_cab_dir/ppviewer.cab"; then
                    success "Cambria Regular (cambria.ttc) installed"
                else
                    warn "Failed to extract cambria.ttc from PowerPointViewer cabinet"
                fi
            else
                warn "Failed to download PowerPointViewer cabinet for Cambria Regular"
            fi
            rm -rf "$tmp_cab_dir"
        fi

        # 2. Modern Aptos typeface family (Microsoft 365 default)
        local aptos_base_url="https://raw.githubusercontent.com/XCroatoanX/ttf-aptos/master"
        local aptos_fonts=(
            "aptos.ttf" "aptos-bold.ttf" "aptos-italic.ttf" "aptos-bold-italic.ttf"
            "aptos-light.ttf" "aptos-light-italic.ttf" "aptos-semibold.ttf" "aptos-semibold-italic.ttf"
            "aptos-extrabold.ttf" "aptos-extrabold-italic.ttf" "aptos-black.ttf" "aptos-black-italic.ttf"
            "aptos-narrow.ttf" "aptos-narrow-bold.ttf" "aptos-narrow-italic.ttf" "aptos-narrow-bold-italic.ttf"
            "aptos-mono.ttf" "aptos-mono-bold.ttf" "aptos-mono-italic.ttf" "aptos-mono-bold-italic.ttf"
            "aptos-serif.ttf" "aptos-serif-bold.ttf" "aptos-serif-italic.ttf" "aptos-serif-bold-italic.ttf"
        )
        local aptos_count=0
        for font in "${aptos_fonts[@]}"; do
            if [[ ! -f "$ms_fonts_dir/$font" ]]; then
                if run curl -fsSL --max-time 30 -o "$ms_fonts_dir/$font" "$aptos_base_url/$font"; then
                    ((aptos_count++))
                fi
            fi
        done
        [[ $aptos_count -gt 0 ]] && success "Aptos font family installed ($aptos_count fonts)"

        # 3. Segoe UI typeface family
        local segoe_base_url="https://raw.githubusercontent.com/mrbvrz/segoe-ui-linux/master/font"
        local segoe_fonts=(
            "segoeui.ttf" "segoeuib.ttf" "segoeuii.ttf" "segoeuiz.ttf"
            "seguisb.ttf" "seguisbi.ttf" "seguisym.ttf"
        )
        local segoe_count=0
        for font in "${segoe_fonts[@]}"; do
            if [[ ! -f "$ms_fonts_dir/$font" ]]; then
                if run curl -fsSL --max-time 30 -o "$ms_fonts_dir/$font" "$segoe_base_url/$font"; then
                    ((segoe_count++))
                fi
            fi
        done
        [[ $segoe_count -gt 0 ]] && success "Segoe UI font family installed ($segoe_count fonts)"
    else
        dry "Download and extract Cambria Regular (cambria.ttc) from PowerPointViewer"
        dry "Download Aptos font family (Microsoft 365 default) into ~/.local/share/fonts/ms-fonts/"
        dry "Download Segoe UI font family into ~/.local/share/fonts/ms-fonts/"
    fi

    log "Downloading FiraCode Nerd Font..."
    if ! $DRY_RUN; then
        mkdir -p ~/.local/share/fonts
        if github_download "ryanoasis/nerd-fonts" "FiraCode\\.zip" "/tmp/FiraCode.zip" \
            "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip"; then
            unzip -oq /tmp/FiraCode.zip -d ~/.local/share/fonts/ && rm -f /tmp/FiraCode.zip
            success "FiraCode Nerd Font installed"
        else
            warn "Failed to download FiraCode Nerd Font"
            info "Manual download: https://github.com/ryanoasis/nerd-fonts/releases"
        fi
        fc-cache -fv

        if command -v gsettings &>/dev/null; then
            log "Configuring FiraCode Nerd Font as default monospace & terminal font..."
            run gsettings set org.gnome.desktop.interface monospace-font-name 'FiraCode Nerd Font 11' 2>/dev/null || true
            run gsettings set org.gnome.Ptyxis font-name 'FiraCode Nerd Font 12' 2>/dev/null || true
            run gsettings set org.gnome.Ptyxis use-system-font false 2>/dev/null || true
        fi
    else
        dry "Download and install FiraCode Nerd Font"
        dry "fc-cache -fv"
        dry "Configure FiraCode Nerd Font in GNOME desktop and Ptyxis terminal"
    fi

    log "Downloading Symbols Nerd Font (universal glyphs & fontconfig)..."
    if ! $DRY_RUN; then
        mkdir -p ~/.local/share/fonts/NerdFonts ~/.config/fontconfig/conf.d
        if github_download "ryanoasis/nerd-fonts" "NerdFontsSymbolsOnly\\.tar\\.xz" "/tmp/NerdFontsSymbolsOnly.tar.xz" \
            "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.tar.xz"; then
            tar -xf /tmp/NerdFontsSymbolsOnly.tar.xz -C ~/.local/share/fonts/NerdFonts/ SymbolsNerdFont-Regular.ttf SymbolsNerdFontMono-Regular.ttf 2>/dev/null || \
                tar -xf /tmp/NerdFontsSymbolsOnly.tar.xz -C ~/.local/share/fonts/NerdFonts/ 2>/dev/null || true
            tar -xf /tmp/NerdFontsSymbolsOnly.tar.xz -C ~/.config/fontconfig/conf.d/ 10-nerd-font-symbols.conf 2>/dev/null || true
            rm -f /tmp/NerdFontsSymbolsOnly.tar.xz
            success "Symbols Nerd Font and fontconfig rules installed"
        else
            warn "Failed to download Symbols Nerd Font"
            info "Manual download: https://github.com/ryanoasis/nerd-fonts/releases"
        fi
        fc-cache -fv 2>/dev/null || true
    else
        dry "Download and install Symbols Nerd Font and 10-nerd-font-symbols.conf fontconfig"
    fi

    step_complete "Fonts installed"
}

# ==============================================================================
# GNOME Tools
# ==============================================================================
setup_gnome() {
    log "Installing GNOME tools and extensions..."
    run_sudo dnf install -y gnome-tweaks gnome-shell-extension-gsconnect gnome-shell-extension-appindicator

    # Enable firewall service for GSConnect / KDE Connect
    if command -v firewall-cmd &>/dev/null; then
        if ! $DRY_RUN; then
            if systemctl is-active --quiet firewalld 2>/dev/null; then
                run_sudo firewall-cmd --permanent --add-service=kdeconnect 2>/dev/null || true
                run_sudo firewall-cmd --reload 2>/dev/null || true
                success "Firewall service enabled for GSConnect / KDE Connect"
            fi
        else
            dry "firewall-cmd --permanent --add-service=kdeconnect && firewall-cmd --reload"
        fi
    fi

    if ! $DRY_RUN; then
        mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
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
        success "Transparent headerbar CSS deployed for GTK3/GTK4"
    else
        dry "Deploy transparent titlebar CSS to ~/.config/gtk-3.0/gtk.css and ~/.config/gtk-4.0/gtk.css"
    fi

    # Silence the "Window is not responding" freeze dialog during Wine/Proton shader compilation
    if command -v gsettings &>/dev/null; then
        if ! $DRY_RUN; then
            gsettings set org.gnome.mutter check-alive-timeout 0 2>/dev/null || true
            success "GNOME Mutter check-alive-timeout set to 0 (silences Proton shader compilation freeze dialogs)"
        else
            dry "gsettings set org.gnome.mutter check-alive-timeout 0"
        fi

        # Personal profile: top bar clock display (show seconds and weekday)
        if [[ "$PROFILE" == "personal" ]]; then
            log "Configuring personal top bar clock display (seconds & weekday)..."
            if ! $DRY_RUN; then
                gsettings set org.gnome.desktop.interface clock-show-seconds true 2>/dev/null || true
                gsettings set org.gnome.desktop.interface clock-show-weekday true 2>/dev/null || true
                success "Top bar clock configured (seconds and weekday enabled)"
            else
                dry "gsettings set org.gnome.desktop.interface clock-show-seconds true"
                dry "gsettings set org.gnome.desktop.interface clock-show-weekday true"
            fi
        fi
    fi

    step_complete "GNOME tools and GSConnect configured"
}

# ==============================================================================
# Essential Packages
# ==============================================================================
setup_packages() {
    log "Installing essential packages..."

    local pkgs_to_install=(
        fastfetch bat eza fd-find ripgrep fzf zoxide wget btop duf plocate tree compsize \
        unzip unrar p7zip p7zip-plugins ntfs-3g gparted timeshift vlc qbittorrent wl-clipboard \
        wmctrl vim libva-utils gstreamer1-plugin-openh264 telegram-desktop android-tools
    )

    if is_gaming_profile; then
        pkgs_to_install+=(steam mangohud gamemode)
    fi

    if is_creator_profile; then
        pkgs_to_install+=(obs-studio akmod-v4l2loopback v4l-utils gtk4-devel libadwaita-devel gstreamer1-devel libayatana-appindicator-gtk3 pulseaudio-utils)
    fi

    run_sudo dnf install -y --skip-unavailable "${pkgs_to_install[@]}"

    run_sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

    if is_gaming_profile; then
        log "Unlocking Steam H264 codec..."
        if ! $DRY_RUN; then
            local unlock_pid
            if flatpak list 2>/dev/null | grep -q "com.valvesoftware.Steam"; then
                info "Flatpak Steam detected"
                xdg-open steam://unlockh264/ 2>/dev/null &
                unlock_pid=$!
            else
                steam steam://unlockh264/ 2>/dev/null &
                unlock_pid=$!
            fi
            sleep 2
            kill "$unlock_pid" 2>/dev/null || true
        else
            dry "Unlock Steam H264 codec"
        fi

        info "Steam Settings (configure manually):"
        info "  • Library → Enable 'Show Steam Deck compatibility info'"
        info "  • Downloads → Disable 'Shader Pre-Caching'"
        info "  • Interface → Client Beta Participation → Steam Beta Update"

        if command -v mangohud &>/dev/null || $DRY_RUN; then
            if ! $DRY_RUN; then
                mkdir -p "$HOME/.config/MangoHud"
                backup_file "$HOME/.config/MangoHud/MangoHud.conf"
                cat > "$HOME/.config/MangoHud/MangoHud.conf" <<'EOF'
gpu_stats
gpu_temp
gpu_core_clock
gpu_mem_clock
gpu_power
cpu_stats
cpu_temp
cpu_mhz
cpu_power
vram
ram
fps
frametime=1
frame_timing=1
hud_no_margin
table_columns=3
background_alpha=0.4
font_size=32
round_corners=8
EOF
                success "MangoHud config created"
                if [[ -d "$HOME/.var/app/com.heroicgameslauncher.hgl" ]]; then
                    mkdir -p "$HOME/.var/app/com.heroicgameslauncher.hgl/config/MangoHud"
                    cp -p "$HOME/.config/MangoHud/MangoHud.conf" "$HOME/.var/app/com.heroicgameslauncher.hgl/config/MangoHud/MangoHud.conf" 2>/dev/null || true
                fi
            else
                dry "Create ~/.config/MangoHud/MangoHud.conf"
            fi
        fi

        # Heroic Games Launcher (Epic, GOG & Sideloaded Games)
        echo ""
        info "Heroic Games Launcher (Epic, GOG & Amazon Games):"
        info "  • Recommended Flatpak installation with Proton/Wine compatibility, MangoHud integration, and offline library support."
        info "  • Recommendation: Install if you play games from Epic Games, GOG, or sideloaded PC games. Otherwise skip."
        if confirm "Install Heroic Games Launcher via Flatpak (Flathub)?" "Y"; then
            if ! $DRY_RUN; then
                # Remove legacy RPM package if previously installed to prevent dual-installation conflicts
                if rpm -q heroic &>/dev/null; then
                    info "Removing legacy Heroic RPM package..."
                    run_sudo dnf remove -y heroic 2>/dev/null || true
                fi

                if flatpak list 2>/dev/null | grep -q "com.heroicgameslauncher.hgl"; then
                    info "Heroic Games Launcher Flatpak is already installed"
                else
                    log "Installing Heroic Games Launcher from Flathub..."
                    if run flatpak install -y flathub com.heroicgameslauncher.hgl 2>/dev/null; then
                        success "Heroic Games Launcher Flatpak installed"
                    else
                        warn "Failed to install Heroic Games Launcher Flatpak"
                    fi
                fi

                # Pre-create standard game prefix directory tree to prevent file picker errors on initial 'Add Game'
                mkdir -p "$HOME/Games/Heroic/Prefixes/shared"

                # Pre-seed or update optimized Heroic configuration (disable UMU container exit delay, enable MangoHud)
                local prime_val="false"
                if lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -qi nvidia; then
                    prime_val="true"
                fi

                local heroic_config_dirs=(
                    "$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic"
                    "$HOME/.config/heroic"
                )

                for h_dir in "${heroic_config_dirs[@]}"; do
                    mkdir -p "$h_dir"
                    local h_cfg="$h_dir/config.json"
                    if [[ ! -f "$h_cfg" ]]; then
                        cat > "$h_cfg" <<HEROIC_EOF
  {
    "defaultSettings": {
      "autoInstallDxvk": true,
      "autoInstallVkd3d": true,
      "autoInstallDxvkNvapi": true,
      "defaultInstallPath": "$HOME/Games/Heroic",
      "defaultSteamPath": "$HOME/.steam/steam",
      "defaultWinePrefix": "$HOME/Games/Heroic/Prefixes",
      "defaultWinePrefixDir": "$HOME/Games/Heroic/Prefixes",
      "winePrefix": "$HOME/Games/Heroic/Prefixes/shared",
      "disableUMU": true,
      "showMangohud": true,
      "useGameMode": true,
      "enableEsync": true,
      "enableFsync": true,
      "nvidiaPrime": $prime_val
    },
    "version": "v0"
  }
HEROIC_EOF
                    else
                        if command -v jq &>/dev/null; then
                            local updated_cfg
                            updated_cfg=$(jq '.defaultSettings.disableUMU = true | .defaultSettings.showMangohud = true' "$h_cfg" 2>/dev/null || true)
                            if [[ -n "$updated_cfg" ]]; then
                                echo "$updated_cfg" > "$h_cfg"
                            fi
                        fi
                    fi
                done

                # Ensure MangoHud configuration is deployed to Flatpak sandbox
                if [[ -f "$HOME/.config/MangoHud/MangoHud.conf" ]]; then
                    mkdir -p "$HOME/.var/app/com.heroicgameslauncher.hgl/config/MangoHud"
                    cp -p "$HOME/.config/MangoHud/MangoHud.conf" "$HOME/.var/app/com.heroicgameslauncher.hgl/config/MangoHud/MangoHud.conf" 2>/dev/null || true
                fi

                success "Optimized Heroic config initialized (disableUMU=true, MangoHud=true, Prefixes pre-created)"
            else
                dry "Install Heroic Games Launcher Flatpak (com.heroicgameslauncher.hgl) from Flathub"
                dry "Create directory $HOME/Games/Heroic/Prefixes/shared"
                dry "Configure ~/.var/app/com.heroicgameslauncher.hgl/config/heroic/config.json with disableUMU=true and MangoHud=true"
            fi
        else
            info "Skipping Heroic Games Launcher installation"
        fi
    fi

    # Vesktop (Discord Desktop App with Vencord plugins)
    echo ""
    info "Vesktop (Discord Client with Vencord & Wayland Screen Audio):"
    info "  • Custom Discord desktop app with Vencord plugins, Wayland screen share audio support, and custom themes."
    info "  • Recommendation: Install if you use Discord on Linux. Otherwise skip."
    if confirm "Install Vesktop?" "Y"; then
        if ! $DRY_RUN; then
            local arch
            arch=$(uname -m)
            local fallback_url="https://github.com/Vencord/Vesktop/releases/download/v1.5.3/vesktop-1.5.3.${arch}.rpm"
            log "Downloading Vesktop RPM..."
            if github_download "Vencord/Vesktop" "vesktop.*\.${arch}\.rpm" "/tmp/vesktop.rpm" "$fallback_url"; then
                if run_sudo dnf install -y /tmp/vesktop.rpm 2>/dev/null; then
                    success "Vesktop installed"
                else
                    warn "Vesktop install failed"
                fi
                run rm -f /tmp/vesktop.rpm
            else
                warn "Failed to download Vesktop"
                info "Manual install: https://github.com/Vencord/Vesktop/releases"
            fi
        else
            dry "Download and install Vesktop RPM from GitHub Releases"
        fi
    else
        info "Skipping Vesktop installation"
    fi

    # Stirling-PDF (Full-featured offline/desktop PDF tool suite)
    if ! command -v stirling-pdf &>/dev/null && ! rpm -q stirling-pdf &>/dev/null; then
        echo ""
        info "Stirling-PDF (Offline Desktop PDF Swiss Army Knife):"
        info "  • Full-featured offline desktop PDF tool suite for splitting, merging, converting, OCR, signing, and editing."
        info "  • Recommendation: Install if you work with PDF documents frequently. Otherwise skip."
        if confirm "Install Stirling-PDF?" "Y"; then
            if ! $DRY_RUN; then
                log "Installing Stirling-PDF..."
                local stirling_rpm="/tmp/stirling-pdf.rpm"
                local stirling_fallback="https://github.com/Stirling-Tools/Stirling-PDF/releases/latest/download/Stirling-PDF-linux-x86_64.rpm"
                if curl -fsSL "https://files.stirlingpdf.com/linux-installer.rpm" -o "$stirling_rpm" 2>/dev/null || \
                   github_download "Stirling-Tools/Stirling-PDF" "Stirling-PDF-linux-.*\.rpm" "$stirling_rpm" "$stirling_fallback"; then
                    if run_sudo dnf install -y "$stirling_rpm" 2>/dev/null; then
                        success "Stirling-PDF installed"
                    else
                        warn "Stirling-PDF RPM install failed"
                    fi
                    run rm -f "$stirling_rpm"
                else
                    warn "Could not download Stirling-PDF RPM"
                fi
            else
                dry "Download and install Stirling-PDF from https://files.stirlingpdf.com/linux-installer.rpm"
            fi
        else
            info "Skipping Stirling-PDF installation"
        fi
    fi

    # NVIDIA Broadcast for Linux (AI Noise Removal, Virtual Camera, Room Echo Removal)
    if is_creator_profile && lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -qi nvidia; then
        if [[ ! -d "$HOME/nvidia-broadcast-linux" || ! -f "$HOME/.local/bin/nvbroadcast" ]]; then
            echo ""
            info "NVIDIA Broadcast for Linux (AI Noise Removal & Virtual Camera FX):"
            info "  • Real-time AI noise removal, room echo elimination, and virtual camera effects for NVIDIA GPUs."
            info "  • Recommendation: Install if you stream, record, or attend meetings with an NVIDIA RTX/GTX GPU. Otherwise skip."
            if confirm "Install NVIDIA Broadcast for Linux?" "Y"; then
                if ! $DRY_RUN; then
                    log "Installing NVIDIA Broadcast for Linux..."
                    if [[ ! -d "$HOME/nvidia-broadcast-linux" ]]; then
                        git clone --depth 1 --branch v1.5.2 https://github.com/Hkshoonya/nvidia-broadcast-linux.git "$HOME/nvidia-broadcast-linux" || true
                    fi
                    if [[ -f "$HOME/nvidia-broadcast-linux/install.sh" ]]; then
                        (cd "$HOME/nvidia-broadcast-linux" && ./install.sh --runtime cuda) || warn "NVIDIA Broadcast install finished with warnings"
                    fi
                else
                    dry "Clone and install NVIDIA Broadcast for Linux (NVIDIA GPU)"
                fi
            else
                info "Skipping NVIDIA Broadcast installation"
            fi
        fi
    fi

    # Personal Profile Suite: ONLYOFFICE swap, Cliamp, and ani-cli
    if [[ "$PROFILE" == "personal" ]]; then
        log "Setting up personal productivity & media tools (ONLYOFFICE, cliamp & ani-cli)..."
        if ! $DRY_RUN; then
            # 1. Swap LibreOffice with ONLYOFFICE Desktop Editors
            log "Configuring personal office suite (ONLYOFFICE Desktop Editors)..."
            if rpm -qa "libreoffice*" 2>/dev/null | grep -q libreoffice || command -v libreoffice &>/dev/null; then
                log "Removing LibreOffice in favor of ONLYOFFICE..."
                run_sudo dnf remove -y "libreoffice*" 2>/dev/null || true
                success "LibreOffice removed"
            fi

            if ! rpm -q onlyoffice-desktopeditors &>/dev/null; then
                log "Installing ONLYOFFICE Desktop Editors..."
                if run_sudo dnf install -y https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors.x86_64.rpm; then
                    success "ONLYOFFICE Desktop Editors installed"
                else
                    warn "Failed to install ONLYOFFICE Desktop Editors RPM"
                fi
            else
                info "ONLYOFFICE Desktop Editors is already installed"
            fi

            mkdir -p "$HOME/.local/bin" "$HOME/.config/cliamp" "$HOME/.config/yt-dlp"
            run_sudo dnf install -y --skip-unavailable mpv 2>/dev/null || true

            # 1. yt-dlp & python dependencies for cliamp
            if ! command -v yt-dlp &>/dev/null; then
                log "Installing yt-dlp standalone binary..."
                if curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o "$HOME/.local/bin/yt-dlp" 2>/dev/null; then
                    [[ -f "$HOME/.local/bin/yt-dlp" ]] && chmod +x "$HOME/.local/bin/yt-dlp"
                fi
            fi
            cat > "$HOME/.config/yt-dlp/config" <<'YTDLP_CONF'
--js-runtimes node
YTDLP_CONF

            # Python SecretStorage for GNOME Keyring cookie decryption
            if command -v python3 &>/dev/null; then
                python3 -m pip install --user secretstorage cryptography jeepney 2>/dev/null || true
            fi

            # 2. cliamp
            if ! command -v cliamp &>/dev/null; then
                log "Installing cliamp retro music player..."
                local cliamp_arch="amd64"
                [[ "$(uname -m)" == "aarch64" ]] && cliamp_arch="arm64"
                if github_download "bjarneo/cliamp" "cliamp-linux-${cliamp_arch}" "$HOME/.local/bin/cliamp"; then
                    chmod +x "$HOME/.local/bin/cliamp"
                    success "cliamp installed"
                else
                    warn "Failed to download cliamp release binary"
                fi
            fi

            # Deploy cliamp YouTube Music configuration
            backup_file "$HOME/.config/cliamp/config.toml"
            cat > "$HOME/.config/cliamp/config.toml" <<'CLIAMP_CONF'
provider = "ytmusic"
theme = ""

[ytmusic]
cookies_from = "chrome+gnomekeyring"
CLIAMP_CONF
            success "cliamp installed and configured with YouTube Music"

            # 3. ani-cli (with hianime provider patch)
            log "Installing ani-cli (patched provider)..."
            if curl -fsSL https://raw.githubusercontent.com/pystardust/ani-cli/refs/pull/1897/head/ani-cli -o "$HOME/.local/bin/ani-cli" 2>/dev/null; then
                [[ -f "$HOME/.local/bin/ani-cli" ]] && chmod +x "$HOME/.local/bin/ani-cli"
                success "ani-cli installed with working provider to ~/.local/bin/ani-cli"
            else
                warn "Failed to download patched ani-cli"
            fi
        else
            dry "Swap LibreOffice with ONLYOFFICE Desktop Editors (remove libreoffice*, install onlyoffice-desktopeditors RPM)"
            dry "Install cliamp, configure YouTube Music in ~/.config/cliamp/config.toml, and deploy patched ani-cli to ~/.local/bin/ani-cli"
        fi
    fi

    step_complete "Essential packages installed"
}

# ==============================================================================
# Development Tools & Compilers
# ==============================================================================
setup_dev() {
    log "Installing dev tools & libraries..."

    local selected_genres=()
    if [[ -n "${DEV_TYPE:-}" && "$DEV_TYPE" != "all" ]]; then
        IFS=',' read -ra selected_genres <<< "$DEV_TYPE"
    elif [[ "$PROFILE" == "full" || "$PROFILE" == "personal" ]] || $DRY_RUN || ! [ -t 0 ]; then
        selected_genres=("systems" "web" "android" "ai")
    else
        echo ""
        echo -e "${BLUE}Choose your development focus (genres):${NC}"
        echo -e "  1) Systems & Low-Level (C, C++, Rust, CMake, Meson, GDB, Valgrind, Hyperfine)"
        echo -e "  2) Web & Cloud         (Node.js, PNPM/Yarn, Python 3, Docker, jq)"
        echo -e "  3) Android & Mobile    (ADB, Fastboot, Scrcpy, Java JDK, Android Studio)"
        echo -e "  4) Data & AI           (Python 3 Devel, Ruff, CUDA Toolkit with GPU guard)"
        echo -e "  5) Full Suite          (Install all development tools - Recommended)"
        echo ""
        local dev_choice=""
        read -r -p "Enter choice [1-5] (default: 5): " dev_choice
        dev_choice="${dev_choice:-5}"
        case "$dev_choice" in
            1) selected_genres=("systems") ;;
            2) selected_genres=("web") ;;
            3) selected_genres=("android") ;;
            4) selected_genres=("ai") ;;
            *) selected_genres=("systems" "web" "android" "ai") ;;
        esac
    fi

    has_dev_genre() {
        local target="$1"
        for g in "${selected_genres[@]}"; do
            [[ "$g" == "$target" || "$g" == "all" ]] && return 0
        done
        return 1
    }

    local dev_pkgs=(
        meson ninja-build automake autoconf libtool pkg-config bear
        gdb valgrind strace ltrace clang-tools-extra
        bc bison flex protobuf-compiler python3-protobuf libxml2 libxslt
        ImageMagick git-lfs git-filter-repo gnupg lz4 rsync zip
        python3-devel python3-virtualenv python3-wheel python3-setuptools
        openssl-devel zlib-devel elfutils-libelf-devel elfutils-devel gnutls-devel
        hyperfine jq glab
    )

    if has_dev_genre "systems"; then
        dev_pkgs+=(gcc clang llvm make cmake)
    fi

    if has_dev_genre "web"; then
        dev_pkgs+=(nodejs)
    fi

    if has_dev_genre "android"; then
        dev_pkgs+=(java-latest-openjdk java-latest-openjdk-devel maven)
    fi

    if [[ "$PROFILE" == "full" ]]; then
        dev_pkgs+=(
            dpkg-dev
            libX11-devel
            libxkbcommon-x11-devel
            libxcb-devel
            fontconfig-devel
            alsa-lib-devel
        )
    elif [[ "$PROFILE" == "personal" ]]; then
        dev_pkgs+=(
            dpkg-dev
            libX11-devel
            libxkbcommon-x11-devel
            libxcb-devel
            fontconfig-devel
            alsa-lib-devel
        )
    fi

    run_sudo dnf install -y --skip-unavailable "${dev_pkgs[@]}"

    # Systems Genre: Rust Toolchain
    if has_dev_genre "systems"; then
        if confirm "Install full Rust toolchain (rustup, clippy, rust-analyzer)?" "Y"; then
            run_sudo dnf install -y rust cargo rustup rustfmt clippy rust-analyzer 2>/dev/null || true
        fi
    fi

    # Android Genre: Android Studio (Flatpak)
    if has_dev_genre "android"; then
        echo ""
        info "Android Studio (Official Android IDE & Virtual Device Emulator):"
        info "  • Complete IDE for Android app development, SDK manager, and hardware-accelerated emulator."
        info "  • Recommendation: Install if you develop Android apps. Skip if you only need ADB/Fastboot."
        if confirm "Install Android Studio (via Flathub)?" "Y"; then
            run flatpak install -y flathub com.google.AndroidStudio 2>/dev/null || warn "Failed to install Android Studio Flatpak"
        else
            info "Skipping Android Studio installation"
        fi
    fi

    # Data & AI Genre: Hardware-Gated NVIDIA CUDA Failsafe
    if has_dev_genre "ai"; then
        if lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -qi nvidia; then
            echo ""
            info "NVIDIA GPU Detected for Data & AI:"
            info "  • CUDA development packages provide headers & libraries for native PyTorch/TensorRT acceleration."
            info "  • Recommendation: Install if you compile custom CUDA kernels or native ML extensions."
            if confirm "Install NVIDIA CUDA development libraries?" "Y"; then
                run_sudo dnf install -y --skip-unavailable xorg-x11-drv-nvidia-cuda-devel 2>/dev/null || true
            fi
        else
            if lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -qi amd; then
                info "AMD GPU detected: Skipping NVIDIA CUDA. (AMD uses ROCm for PyTorch/ML acceleration)"
            else
                info "Non-NVIDIA system detected: Skipping CUDA installation safely."
            fi
        fi
    fi

    # ccache compiler cache configuration
    if [[ "$PROFILE" == "personal" ]] || { command -v ccache &>/dev/null || $DRY_RUN; }; then
        if ! $DRY_RUN; then
            ccache --set-config=max_size=50G 2>/dev/null || true
            ccache --set-config=compression=true 2>/dev/null || true
            mkdir -p "$HOME/.ccache"
            echo "cache_dir = $HOME/.ccache" > "$HOME/.ccache/ccache.conf"
            success "ccache configured (50GB limit, compressed)"
        else
            dry "Configure ccache: 50GB max size, compression enabled"
        fi
    fi

    # Web Genre: Corepack for yarn/pnpm
    if has_dev_genre "web" && command -v npm &>/dev/null; then
        log "Enabling corepack (yarn/pnpm)..."
        run_sudo npm install -g corepack 2>/dev/null || true
        run_sudo corepack enable 2>/dev/null || true
    fi

    log "Configuring Python development symlinks..."
    if ! $DRY_RUN; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v python3 || echo /usr/bin/python3)" "$HOME/.local/bin/python" 2>/dev/null || true
        ln -sf "$(command -v python3 || echo /usr/bin/python3)" "$HOME/.local/bin/python3" 2>/dev/null || true
        success "Python symlinks configured in ~/.local/bin"
    else
        dry "Create python symlinks in ~/.local/bin"
    fi

    # Git global defaults (suppress pagers, auto-setup remote, pull rebase)
    if command -v git &>/dev/null || $DRY_RUN; then
        if ! $DRY_RUN; then
            git config --global core.pager cat 2>/dev/null || true
            git config --global push.autoSetupRemote true 2>/dev/null || true
            git config --global pull.rebase true 2>/dev/null || true
            git config --global diff.colorMoved zebra 2>/dev/null || true
            success "Git global defaults configured (pager suppressed, auto remote tracking)"
        else
            dry "Configure git global defaults (core.pager cat, autoSetupRemote true, pull.rebase true)"
        fi
    fi

    # PostgreSQL 18 Server (PGDG Official Repository)
    local install_pg=false
    if [[ "$PROFILE" == "personal" ]]; then
        install_pg=true
    elif [[ "$PROFILE" == "full" ]]; then
        if confirm "Install and configure PostgreSQL 18 Server & pgAdmin 4?" "N"; then
            install_pg=true
        fi
    fi

    if $install_pg; then
        log "Installing PostgreSQL 18 Server..."
        if ! $DRY_RUN; then
            local fedora_ver
            fedora_ver=$(rpm -E %fedora 2>/dev/null || echo "44")
            local arch
            arch=$(uname -m)
            local pgdg_rpm="https://download.postgresql.org/pub/repos/yum/reporpms/F-${fedora_ver}-${arch}/pgdg-fedora-repo-latest.noarch.rpm"
            if ! rpm -q pgdg-fedora-repo &>/dev/null; then
                run_sudo dnf install -y --skip-unavailable "$pgdg_rpm" 2>/dev/null || true
            fi
            if run_sudo dnf install -y postgresql18-server postgresql18 postgresql18-libs; then
                if [[ ! -f "/var/lib/pgsql/18/data/PG_VERSION" ]]; then
                    log "Initializing PostgreSQL 18 database cluster..."
                    run_sudo /usr/pgsql-18/bin/postgresql-18-setup initdb 2>/dev/null || true
                fi
                run_sudo systemctl enable --now postgresql-18 2>/dev/null || true
                if [[ -d "/usr/pgsql-18/bin" ]]; then
                    run_sudo tee /etc/profile.d/pgsql18.sh > /dev/null <<'PG_PROFILE'
export PATH="/usr/pgsql-18/bin:$PATH"
PG_PROFILE
                fi
                success "PostgreSQL 18 installed, initialized, and enabled"
            else
                warn "PostgreSQL 18 installation failed"
            fi
        else
            dry "Install pgdg-fedora-repo, postgresql18-server, run initdb, and enable postgresql-18.service"
        fi

        # pgAdmin 4 (Official PostgreSQL Administration GUI)
        log "Installing pgAdmin 4 Desktop..."
        if ! $DRY_RUN; then
            local pgadmin_repo_rpm="https://ftp.postgresql.org/pub/pgadmin/pgadmin4/yum/pgadmin4-fedora-repo-2-1.noarch.rpm"
            if ! rpm -q pgadmin4-fedora-repo &>/dev/null; then
                run_sudo dnf install -y --skip-unavailable "$pgadmin_repo_rpm" 2>/dev/null || true
            fi
            if run_sudo dnf install -y pgadmin4-desktop; then
                success "pgAdmin 4 Desktop installed"
            else
                warn "pgAdmin 4 installation failed"
            fi
        else
            dry "Install pgadmin4-fedora-repo and pgadmin4-desktop via dnf"
        fi
    fi

    step_complete "Dev tools installed"
}

# ==============================================================================
# Code Editor Selection & Configuration
# ==============================================================================
setup_editor() {
    log "Configuring Code Editor..."

    echo ""
    echo -e "${BLUE}Choose your primary code editor:${NC}"
    echo -e "  ${GREEN}1) Zed (Recommended)${NC}"
    echo -e "  2) VS Codium"
    echo -e "  3) Anti gravity IDE"
    echo -e "  ${YELLOW}4) VS Code (Not recommended)${NC}"
    echo -e "  5) Skip editor installation"
    echo ""

    local editor_choice=""
    if $DRY_RUN; then
        editor_choice="1"
        dry "Prompt user for Code Editor selection: [1] Zed (Recommended), [2] VS Codium, [3] Antigravity IDE, [4] VS Code (Not recommended), [5] Skip"
    else
        read -r -p "Enter choice [1-5] (default: 1): " editor_choice
        editor_choice="${editor_choice:-1}"
    fi

    case "$editor_choice" in
        1)
            log "Installing and configuring Zed Editor (Recommended)..."
            if ! $DRY_RUN; then
                if ! command -v zed &>/dev/null; then
                    local zed_installer
                    zed_installer=$(mktemp /tmp/zed-install-XXXXXX.sh)
                    if curl --proto '=https' --tlsv1.2 -fsSL https://zed.dev/install.sh -o "$zed_installer"; then
                        if bash "$zed_installer" 2>/dev/null; then
                            success "Zed installed via official installer script"
                        else
                            warn "Zed installation failed - install manually from https://zed.dev"
                        fi
                        rm -f "$zed_installer"
                    else
                        warn "Failed to download Zed installer from https://zed.dev"
                        rm -f "$zed_installer"
                    fi
                fi

                # Deploy Zed configurations
                mkdir -p "$HOME/.config/zed" "$HOME/.local/bin"
                backup_file "$HOME/.config/zed/settings.json"
                cat > "$HOME/.config/zed/settings.json" <<'ZED_SETTINGS'
{
  "agent": {
    "sidebar_side": "right",
    "favorite_models": [],
    "model_parameters": []
  },
  "project_panel": {
    "dock": "left"
  },
  "icon_theme": "Catppuccin Mocha",
  "session": {},
  "terminal": {
    "font_size": 15.0,
    "font_family": "FiraCode Nerd Font"
  },
  "minimap": {
    "show": "always"
  },
  "autosave": {
    "after_delay": {
      "milliseconds": 1000
    }
  },
  "buffer_font_fallbacks": [
    "Fira Code",
    "JetBrains Mono",
    "monospace"
  ],
  "buffer_font_family": "FiraCode Nerd Font",
  "base_keymap": "VSCode",
  "ui_font_size": 16,
  "buffer_font_size": 16.0,
  "theme": {
    "mode": "system",
    "light": "Ayu Light",
    "dark": "Catppuccin Mocha"
  }
}
ZED_SETTINGS

                backup_file "$HOME/.config/zed/keymap.json"
                cat > "$HOME/.config/zed/keymap.json" <<'ZED_KEYMAP'
[
  {
    "context": "Workspace",
    "bindings": {
      "ctrl-alt-n": ["task::Spawn", { "task_name": "Run current file" }],
      "f5": ["task::Spawn", { "task_name": "Run current file" }],
      "ctrl-f5": ["task::Rerun", { "reevaluate_context": true }]
    }
  },
  {
    "context": "Editor",
    "bindings": {
      "ctrl-alt-n": ["task::Spawn", { "task_name": "Run current file" }],
      "f5": ["task::Spawn", { "task_name": "Run current file" }]
    }
  }
]
ZED_KEYMAP

                backup_file "$HOME/.config/zed/tasks.json"
                cat > "$HOME/.config/zed/tasks.json" <<'ZED_TASKS'
[
  {
    "label": "Run current file",
    "command": "zed-run",
    "args": ["$ZED_FILE"],
    "use_new_terminal": false,
    "allow_concurrent_runs": false,
    "reveal": "always",
    "hide": "always",
    "show_summary": false,
    "show_command": false
  }
]
ZED_TASKS

                backup_file "$HOME/.local/bin/zed-run"
                cat > "$HOME/.local/bin/zed-run" <<'ZED_RUN'
#!/usr/bin/env bash

FILE="$1"
if [ -z "$FILE" ]; then
    echo "[Zed Runner] No file provided."
    exec "${SHELL:-/bin/zsh}"
fi

EXT="${FILE##*.}"
DIR="$(dirname "$FILE")"
NAME="$(basename "$FILE")"
BASE="${NAME%.*}"

# Trap Ctrl+C (SIGINT) and SIGTERM so the runner drops into the shell instead of aborting
drop_to_shell() {
    echo ""
    echo -e "\033[1;30m----------------------------------------\033[0m"
    echo -e "\033[1;33m[Program interrupted (Ctrl+C). Interactive terminal active:]\033[0m"
    exec "${SHELL:-/bin/zsh}"
}

trap drop_to_shell INT TERM

echo -e "\033[1;34m==>\033[0m \033[1;32mRunning:\033[0m $NAME"
cd "$DIR"

case "$EXT" in
    py)
        python3 "$FILE"
        ;;
    rs)
        if [ -f "Cargo.toml" ] || [ -f "../Cargo.toml" ] || [ -f "../../Cargo.toml" ]; then
            cargo run
        else
            rustc "$FILE" -o "/tmp/$BASE" && "/tmp/$BASE"
        fi
        ;;
    c)
        gcc -O2 "$FILE" -o "/tmp/$BASE" -lm && "/tmp/$BASE"
        ;;
    cpp|cc|cxx)
        g++ -O2 "$FILE" -o "/tmp/$BASE" && "/tmp/$BASE"
        ;;
    go)
        go run "$FILE"
        ;;
    js)
        node "$FILE"
        ;;
    ts)
        npx tsx "$FILE" 2>/dev/null || npx ts-node "$FILE"
        ;;
    sh|bash)
        bash "$FILE"
        ;;
    lua)
        lua "$FILE"
        ;;
    html)
        xdg-open "$FILE"
        ;;
    *)
        echo "[Zed Runner] Unsupported file type: .$EXT"
        ;;
esac

echo ""
echo -e "\033[1;30m----------------------------------------\033[0m"
echo -e "\033[1;36m[Program finished. Interactive terminal active:]\033[0m"
exec "${SHELL:-/bin/zsh}"
ZED_RUN
                chmod +x "$HOME/.local/bin/zed-run"
                success "Zed Editor installed and configured"
            else
                dry "Install Zed via official installer script and deploy settings.json, keymap.json, tasks.json & zed-run"
            fi
            ;;

        2)
            log "Installing and configuring VS Codium (FLOSS)..."
            if ! $DRY_RUN; then
                run_sudo rpm --import https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg 2>/dev/null || true
                run_sudo tee /etc/yum.repos.d/vscodium.repo > /dev/null <<'EOL'
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
EOL
                if run_sudo dnf makecache; then
                    run_sudo dnf install -y codium || warn "Failed to install VSCodium"
                else
                    warn "Failed to refresh VSCodium repo metadata"
                fi

                mkdir -p "$HOME/.config/VSCodium/User"
                backup_file "$HOME/.config/VSCodium/User/settings.json"
                cat > "$HOME/.config/VSCodium/User/settings.json" <<'VSCODIUM_SETTINGS'
{
    "editor.fontFamily": "'FiraCode Nerd Font', 'Fira Code', monospace",
    "editor.fontWeight": "600",
    "editor.fontLigatures": true,
    "editor.fontSize": 14,
    "editor.lineHeight": 1.6,
    "terminal.integrated.fontFamily": "'FiraCode Nerd Font', monospace",
    "terminal.integrated.fontWeight": "600",
    "terminal.integrated.fontSize": 14,
    "terminal.integrated.lineHeight": 1.2,
    "terminal.integrated.defaultProfile.linux": "zsh",
    "files.autoSave": "afterDelay",
    "workbench.iconTheme": "vscode-icons"
}
VSCODIUM_SETTINGS
                success "VS Codium installed and settings configured"
            else
                dry "Add VSCodium repo, install codium, and configure settings.json"
            fi
            ;;

        3)
            log "Installing and configuring Google Antigravity IDE..."
            if ! $DRY_RUN; then
                if ! command -v agy &>/dev/null; then
                    local agy_installer
                    agy_installer=$(mktemp /tmp/agy-install-XXXXXX.sh)
                    if curl --proto '=https' --tlsv1.2 -fsSL https://antigravity.google/cli/install.sh -o "$agy_installer"; then
                        bash "$agy_installer" 2>/dev/null || \
                            warn "Antigravity install failed - install manually from https://antigravity.google"
                        rm -f "$agy_installer"
                    else
                        warn "Failed to download Antigravity installer from https://antigravity.google/cli/install.sh"
                        rm -f "$agy_installer"
                    fi
                fi
                mkdir -p "$HOME/.config/antigravity" "$HOME/.config/Code/User" "$HOME/.config/VSCodium/User"
                for target_dir in "$HOME/.config/antigravity" "$HOME/.config/Code/User" "$HOME/.config/VSCodium/User"; do
                    if [[ -d "$target_dir" ]]; then
                        backup_file "$target_dir/settings.json"
                        cat > "$target_dir/settings.json" <<'ANTI_SETTINGS'
{
    "editor.fontFamily": "'FiraCode Nerd Font', 'Fira Code', monospace",
    "editor.fontWeight": "600",
    "editor.fontLigatures": true,
    "editor.fontSize": 14,
    "terminal.integrated.fontFamily": "'FiraCode Nerd Font', monospace",
    "terminal.integrated.fontSize": 14,
    "terminal.integrated.defaultProfile.linux": "zsh",
    "files.autoSave": "afterDelay"
}
ANTI_SETTINGS
                    fi
                done
                success "Antigravity IDE installed and configured"
            else
                dry "Install Antigravity CLI/IDE via official script and configure settings"
            fi
            ;;

        4)
            log "Installing and configuring VS Code (Not recommended)..."
            if ! $DRY_RUN; then
                run_sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null || true
                run_sudo tee /etc/yum.repos.d/vscode.repo > /dev/null <<'EOL'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOL
                if run_sudo dnf makecache; then
                    run_sudo dnf install -y code || warn "Failed to install VS Code"
                else
                    warn "Failed to refresh VS Code repo metadata"
                fi

                mkdir -p "$HOME/.config/Code/User"
                backup_file "$HOME/.config/Code/User/settings.json"
                cat > "$HOME/.config/Code/User/settings.json" <<'VSCODE_SETTINGS'
{
    "editor.fontFamily": "'FiraCode Nerd Font', 'Fira Code', monospace",
    "editor.fontWeight": "600",
    "editor.fontLigatures": true,
    "editor.fontSize": 14,
    "editor.lineHeight": 1.6,
    "terminal.integrated.fontFamily": "'FiraCode Nerd Font', monospace",
    "terminal.integrated.fontWeight": "600",
    "terminal.integrated.fontSize": 14,
    "terminal.integrated.lineHeight": 1.2,
    "terminal.integrated.defaultProfile.linux": "zsh",
    "files.autoSave": "afterDelay",
    "workbench.iconTheme": "vscode-icons"
}
VSCODE_SETTINGS
                success "VS Code installed and settings configured"
            else
                dry "Add Microsoft VS Code repo, install code, and configure settings.json"
            fi
            ;;

        5|*)
            info "Skipped code editor installation"
            ;;
    esac

    step_complete "Code editor configured"
}

# ==============================================================================
# Flatpaks
# ==============================================================================
setup_flatpaks() {
    log "Installing Flatpaks..."
    local flatpaks=(org.localsend.localsend_app com.mattjakeman.ExtensionManager)

    run flatpak install -y flathub "${flatpaks[@]}" 2>/dev/null || true

    step_complete "Flatpaks installed"
}

# ==============================================================================
# Docker Setup
# ==============================================================================
# Configure Docker daemon, NetworkManager unmanaged interface, and firewall isolation.
setup_docker() {
    log "Configuring Docker..."

    log "Installing Docker packages..."
    run_sudo dnf install -y docker docker-cli moby-engine containerd freerdp

    if ! rpm -q moby-engine &>/dev/null && ! rpm -q docker-ce &>/dev/null; then
        warn "Docker (moby-engine/docker-ce) not installed - skipping configuration"
        step_complete "Docker (not installed)"
        return 0
    fi

    # Mark docker0 as unmanaged in NetworkManager to prevent route metric conflicts and unintended teardowns
    log "Configuring NetworkManager to ignore docker0..."
    if [[ ! -f /etc/NetworkManager/conf.d/10-docker.conf ]]; then
        run_sudo tee /etc/NetworkManager/conf.d/10-docker.conf >/dev/null <<'EOF'
[keyfile]
unmanaged-devices=interface-name:docker0
EOF
        run_sudo systemctl restart NetworkManager 2>/dev/null || true
        info "NetworkManager configured to ignore docker0"
    else
        info "NetworkManager already configured for Docker"
    fi

    # Prevent firewalld daemon reloads from wiping Docker container forward and NAT iptables rules
    log "Configuring firewall for Docker..."
    if [[ -f /etc/firewalld/firewalld.conf ]]; then
        if ! grep -q "IgnoreInterfaces=docker0" /etc/firewalld/firewalld.conf; then
            if grep -q "^IgnoreInterfaces=" /etc/firewalld/firewalld.conf; then
                run_sudo sed -i 's/^IgnoreInterfaces=.*/IgnoreInterfaces=docker0/' /etc/firewalld/firewalld.conf
            else
                echo "IgnoreInterfaces=docker0" | run_sudo tee -a /etc/firewalld/firewalld.conf >/dev/null
            fi
            run_sudo systemctl restart firewalld 2>/dev/null || true
            info "Firewall configured to ignore docker0 interface"
        else
            info "Firewall already configured for Docker"
        fi
    fi

    run_sudo usermod -aG docker "${USER:-$(id -un)}"

    run_sudo systemctl enable containerd.service 2>/dev/null || true
    # Clear systemd failure rate limit counter before enabling service
    if sudo systemctl is-failed docker &>/dev/null; then
        run_sudo systemctl reset-failed docker 2>/dev/null || true
    fi
    run_sudo systemctl enable --now docker 2>/dev/null || true

    if sudo systemctl is-active --quiet docker; then
        success "Docker running"
        info "After reboot, verify with: docker run --rm hello-world"
    else
        warn "Docker failed to start - check: sudo systemctl status docker"
        info "Common fixes:"
        info "  • Reboot and try again"
        info "  • Check: sudo journalctl -u docker --no-pager -n 20"
    fi

    log "Installing Docker Compose CLI plugin..."
    if ! $DRY_RUN; then
        DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
        mkdir -p "$DOCKER_CONFIG/cli-plugins"
        if [[ ! -f "$DOCKER_CONFIG/cli-plugins/docker-compose" ]]; then
            if github_download "docker/compose" "docker-compose-linux-x86_64$" \
                "$DOCKER_CONFIG/cli-plugins/docker-compose" \
                "https://github.com/docker/compose/releases/download/v5.0.1/docker-compose-linux-x86_64"; then
                chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
                success "Docker Compose installed"
            else
                warn "Failed to download Docker Compose"
                info "Manual download: https://github.com/docker/compose/releases"
            fi
        fi
    else
        dry "Download and install Docker Compose CLI plugin"
    fi

    step_complete "Docker configured"
}

# ==============================================================================
# KVM/QEMU Virtualization Setup
# ==============================================================================
# Configure KVM/QEMU virtualization stack, modular libvirt socket activation, and tuned profile.
setup_kvm() {
    log "Setting up KVM/QEMU Virtualization..."

    # Check for Intel VT-x (vmx) or AMD-V (svm) CPU virtualization extensions in /proc/cpuinfo
    if ! grep -E 'vmx|svm' /proc/cpuinfo &>/dev/null; then
        warn "CPU virtualization (VT-x/AMD-V) not detected or not enabled in BIOS"
        if ! confirm "Continue anyway?" "N"; then
            step_complete "KVM (skipped - no virtualization support)"
            return 0
        fi
    fi

    if confirm "Install KVM/QEMU virtualization packages?" "Y"; then
        log "Installing virtualization packages..."
        run_sudo dnf install -y @virtualization qemu-kvm libvirt virt-install virt-manager libvirt-devel virt-top guestfs-tools gnome-boxes
    fi

    # Switch from legacy monolithic libvirtd daemon to on-demand modular socket activation (virtqemud.socket)
    if confirm "Configure virtualization services (modern socket activation)?" "Y"; then
        log "Configuring virtualization services..."
        run_sudo systemctl disable --now libvirtd.service 2>/dev/null || true
        run_sudo systemctl enable --now virtqemud.socket
        success "Virtualization services configured"
    fi

    if confirm "Configure firewall for libvirt?" "Y"; then
        log "Configuring firewall..."
        run_sudo firewall-cmd --add-service=libvirt --permanent
        run_sudo firewall-cmd --reload
        success "Firewall configured for libvirt"
    fi

    # VirtIO paravirtualized storage/network drivers repository for Windows guest VMs
    echo ""
    info "VirtIO Drivers for Windows Guest VMs:"
    info "  • Paravirtualized storage (virtio-blk/scsi) and network (virtio-net) drivers for Windows guests under KVM/QEMU."
    info "  • Dual-boot note: If you dual boot Windows on bare metal, you do NOT need this."
    info "  • Recommendation: Install only if you specifically plan to run Windows in a virtual machine. Otherwise skip."
    if confirm "Install VirtIO drivers for Windows virtual machines?" "N"; then
        log "Installing VirtIO drivers..."
        run_sudo wget https://fedorapeople.org/groups/virt/virtio-win/virtio-win.repo \
            -O /etc/yum.repos.d/virtio-win.repo 2>/dev/null || warn "Failed to add virtio-win repo"
        run_sudo dnf install -y virtio-win || warn "VirtIO drivers installation failed"
    else
        info "Skipping VirtIO drivers installation"
    fi

    # Apply virtual-host tuned profile for optimized kernel dirty memory ratios and scheduler latency
    if confirm "Enable performance optimizations (tuned virtual-host profile)?" "Y"; then
        log "Enabling performance optimizations..."
        run_sudo systemctl enable --now tuned
        run_sudo tuned-adm profile virtual-host
        success "Performance tuning applied"
    fi

    # Grant local user passwordless access to libvirt hypervisor socket
    if confirm "Add current user to libvirt group?" "Y"; then
        log "Configuring user permissions..."
        run_sudo usermod -aG libvirt "${USER:-$(id -un)}"

        # Default libvirt URI directs virsh and GUI tools to system QEMU daemon
        if [[ -f ~/.bashrc ]] && ! grep -q "LIBVIRT_DEFAULT_URI" ~/.bashrc; then
            backup_file "$HOME/.bashrc"
            echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.bashrc
        fi
        if [[ -f ~/.zshrc ]] && ! grep -q "LIBVIRT_DEFAULT_URI" ~/.zshrc; then
            backup_file "$HOME/.zshrc"
            echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.zshrc
        fi
        success "User added to libvirt group"
    fi

    warn "⚠️  REBOOT REQUIRED for group membership changes"
    info "After reboot, run the following verification commands:"
    info "  1. sudo virt-host-validate qemu"
    info "  2. virsh uri"

    if confirm "Show post-reboot storage and network setup commands?" "Y"; then
        echo ""
        log "Post-reboot commands to run manually:"
        echo ""
        info "Storage permissions fix:"
        echo "  sudo setfacl -b /var/lib/libvirt/images"
        echo "  sudo chgrp libvirt /var/lib/libvirt/images"
        echo "  sudo chmod 775 /var/lib/libvirt/images"
        echo "  sudo chmod g+s /var/lib/libvirt/images"
        echo "  sudo setfacl -m u:\$(whoami):rwx /var/lib/libvirt/images"
        echo "  sudo setfacl -m d:u:\$(whoami):rwx /var/lib/libvirt/images"
        echo ""
        info "Storage pool setup:"
        echo "  virsh pool-destroy default 2>/dev/null || true"
        echo "  virsh pool-undefine default 2>/dev/null || true"
        echo "  virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images"
        echo "  virsh pool-start default"
        echo "  virsh pool-autostart default"
        echo ""
        info "Network setup:"
        echo "  virsh net-start default"
        echo "  virsh net-autostart default"
        echo ""
        info "Verification:"
        echo "  virt-host-validate qemu | grep -E '(PASS|FAIL)'"
        echo "  virsh list --all"
        echo "  virsh net-list --all"
        echo "  virsh pool-info default"
        echo ""
    fi

    step_complete "KVM/QEMU Virtualization configured"
}

# ==============================================================================
# Summary
# ==============================================================================
show_summary() {
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local mins=$((duration / 60)) secs=$((duration % 60))

    echo -e "\n${GREEN}=== INSTALLATION SUMMARY ===${NC}"
    echo "Time: ${mins}m ${secs}s | Steps: ${COMPLETED_STEPS} completed, ${FAILED_STEPS} failed, ${SKIPPED_STEPS} skipped (of ${TOTAL_STEPS})"

    echo "Service Status:"
    systemctl is-active --quiet tlp && echo "  ✅ TLP" || echo "  ❌ TLP"
    systemctl is-active --quiet docker && echo "  ✅ Docker" || echo "  ❌ Docker"
    local default_sh
    default_sh=$(basename "${SHELL:-/bin/bash}")
    if [[ "$default_sh" == "fish" || "$default_sh" == "zsh" ]]; then
        echo "  ✅ Default shell: $default_sh"
    else
        echo "  ℹ️  Default shell: $default_sh"
    fi

    if confirm "Verify hardware video acceleration?" "N"; then
        log "Checking hardware acceleration..."
        echo ""
        echo "H.264 Encoders:"
        command -v ffmpeg >/dev/null && ffmpeg -encoders 2>/dev/null | grep -i "264" | head -5 || echo "  ffmpeg not found"
        echo ""
        echo "VA-API Profiles:"
        command -v vainfo >/dev/null && vainfo 2>/dev/null | grep -i "VAProfileH264" | head -3 || echo "  vainfo not found"
        echo ""
    fi

    echo "Next Steps:"
    echo "1. Reboot your system if you haven't already (Docker group, libvirt group, kernel modules)"
    echo "2. Open a new terminal to start using Fish/ZSH + Starship"
    echo "3. Review the log file: $LOG_FILE"
    echo -e "${GREEN}System ready! 🚀${NC}"
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    parse_args "$@"

    # Enable logging to file only during active execution
    exec > >(tee -a "$LOG_FILE") 2>&1

    if $DRY_RUN; then
        echo -e "\033[0;35m========================================${NC}"
        echo -e "\033[0;35m   DRY-RUN MODE - No changes will be made${NC}"
        echo -e "\033[0;35m========================================${NC}"
        echo ""
    fi

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Fedora 44 Post-Install Setup v${SCRIPT_VERSION}${NC}"
    echo -e "${GREEN}========================================${NC}"
    info "Started at $(date)"
    info "Log file: $LOG_FILE"

    # Architecture verification guard
    local system_arch
    system_arch=$(uname -m)
    if [[ "$system_arch" != "x86_64" ]]; then
        echo ""
        warn "Unsupported CPU architecture detected: $system_arch"
        warn "This script is designed and tested exclusively for x86_64 systems (AMD, Intel, NVIDIA)."
        warn "ARM64 platforms, including Qualcomm Snapdragon X Elite / X Plus laptops, are not supported."
        if ! confirm "Continue anyway at your own risk?" "N"; then
            info "Aborting setup for unsupported architecture ($system_arch)."
            exit 1
        fi
    fi

    # Interactive profile selection menu
    select_profile_menu

    # Refresh sudo timestamp in background subshell loop to prevent auth expiry during long DNF or compilation tasks.
    # Loop terminates automatically when parent script process ($$) exits.
    if ! $DRY_RUN; then
        sudo -v || { error "Requires sudo"; exit 1; }
        while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
        SUDO_PID=$!
    fi

    if confirm "Show currently installed versions?" "N"; then
        show_versions
    fi

    if confirm "Restore from previous backup?" "N"; then
        restore_backups || true
        return 0
    fi

    if ! $DRY_RUN && ! check_network; then
        error "No internet connection. Exiting."
        exit 1
    fi

    if ! $DRY_RUN; then
        check_disk_space 20 "$HOME"
    fi

    # Execution order enforces strict dependency chain:
    # 1. Package manager mirrors & DNS resolution (setup_dnf, setup_dns)
    # 2. Power policies, greeter no-sleep, and system fonts
    # 3. User shell environment (ZSH/Starship) & default browser
    # 4. Domain packages, dev runtimes, container engines & virtualization (setup_dev, setup_docker, setup_kvm)
    # 5. Pre-driver kernel verification checkpoint before building out-of-tree modules
    # 6. GPU driver configuration and Secure Boot MOK guidance (setup_drivers)
    local steps=(
        "setup_dnf:DNF Configuration"
        "setup_dns:DNS Configuration"
        "setup_power:Power Management"
        "setup_nosleep:No-Sleep Settings"
        "setup_fonts:System Fonts"
        "setup_shell:ZSH + Starship"
        "setup_browser_multimedia:Brave + Multimedia"
        "setup_copr:COPR Packages"
        "setup_gnome:GNOME Tools"
        "setup_packages:Essential Packages"
        "setup_dev:Development Tools"
        "setup_editor:Code Editor"
        "setup_flatpaks:Flatpak Apps"
        "setup_docker:Docker Setup"
        "setup_kvm:KVM/QEMU Virtualization"
        "setup_pre_driver_reboot:Pre-Driver Reboot"
        "setup_drivers:GPU Drivers"
    )

    # Step matrices mapping profiles to required setup functions
    local -A PROFILE_STEPS
    PROFILE_STEPS[minimal]="setup_dnf setup_dns setup_fonts setup_shell setup_browser_multimedia setup_pre_driver_reboot setup_drivers"
    PROFILE_STEPS[dev]="setup_dnf setup_dns setup_power setup_nosleep setup_fonts setup_shell setup_browser_multimedia setup_gnome setup_packages setup_dev setup_editor setup_flatpaks setup_docker setup_kvm setup_pre_driver_reboot setup_drivers"
    PROFILE_STEPS[gaming]="setup_dnf setup_dns setup_power setup_fonts setup_shell setup_browser_multimedia setup_gnome setup_packages setup_flatpaks setup_pre_driver_reboot setup_drivers"
    PROFILE_STEPS[workstation]="setup_dnf setup_dns setup_power setup_fonts setup_shell setup_browser_multimedia setup_gnome setup_packages setup_flatpaks setup_pre_driver_reboot setup_drivers"
    PROFILE_STEPS[creator]="setup_dnf setup_dns setup_power setup_fonts setup_shell setup_browser_multimedia setup_gnome setup_packages setup_flatpaks setup_pre_driver_reboot setup_drivers"
    PROFILE_STEPS[full]=""
    PROFILE_STEPS[personal]=""

    info "Profile: $PROFILE"
    [[ -n "${PROFILE_STEPS[$PROFILE]}" ]] && info "Running steps: ${PROFILE_STEPS[$PROFILE]}"

    init_state

    # Filter execution sequence based on active profile and check completion state for idempotency
    local filtered_steps=()
    for step in "${steps[@]}"; do
        IFS=':' read -r func _ <<< "$step"
        if [[ -z "${PROFILE_STEPS[$PROFILE]}" ]] || [[ " ${PROFILE_STEPS[$PROFILE]} " == *" $func "* ]]; then
            filtered_steps+=("$step")
        fi
    done
    TOTAL_STEPS=${#filtered_steps[@]}

    for step in "${filtered_steps[@]}"; do
        IFS=':' read -r func name <<< "$step"

        if is_step_completed "$func" && ! $FORCE_RERUN; then
            info "Already completed: $name (use --force to re-run)"
            COMPLETED_STEPS=$((COMPLETED_STEPS + 1))
            continue
        fi

        echo ""
        echo -e "${BLUE}Step: $name${NC}"
        if confirm "Run this step?" "Y"; then
            local step_status=0
            (
                set -eo pipefail
                $func
            ) || step_status=$?

            if [[ $step_status -eq 0 ]]; then
                if ! $DRY_RUN; then
                    mark_step_completed "$func"
                fi
                COMPLETED_STEPS=$((COMPLETED_STEPS + 1))
            else
                warn "$name had issues (exit status: $step_status)"
                FAILED_STEPS=$((FAILED_STEPS + 1))
            fi
        else
            warn "Skipped: $name"
            SKIPPED_STEPS=$((SKIPPED_STEPS + 1))
        fi
    done

    show_summary

    info "Full log saved to: $LOG_FILE"
    if [[ -d "$BACKUP_DIR" ]]; then
        info "Config backups saved to: $BACKUP_DIR"
    fi
}

cleanup() {
    if [[ -n "${SUDO_PID:-}" ]]; then
        kill "$SUDO_PID" 2>/dev/null || true
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    trap 'echo -e "\n${RED}Interrupted${NC}"; cleanup; exit 1' INT TERM
    trap cleanup EXIT
    main "$@"
fi