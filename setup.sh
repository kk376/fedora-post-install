#!/bin/bash
# Fedora 44 Post-Install Setup Script
# Author: Kushagra Kumar
# Version: 7.0.0

# ==============================================================================
# Configuration & Flags
# ==============================================================================
: "${DRY_RUN:=false}"
: "${UNATTENDED:=false}"
: "${BACKUP_DIR:=$HOME/.config/fedora-setup-backups/$(date +%Y%m%d_%H%M%S)}"
: "${LOG_FILE:=/tmp/fedora-setup-$(date +%Y%m%d_%H%M%S).log}"
: "${SCRIPT_VERSION:=7.0.0}"
: "${PROFILE:=full}"
: "${DEV_TYPE:=all}"
PROFILE_SPECIFIED=false
DEV_TYPE_SPECIFIED=false
: "${FORCE_RERUN:=false}"
: "${STATE_FILE:=$HOME/.config/fedora-setup/state.txt}"
: "${SUDO_PID:=}"

# System hardware globals (populated by detect_hardware)
SYS_ARCH="$(uname -m)"
IS_LAPTOP=false
HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false

# ==============================================================================
# Colors & Logging
# ==============================================================================
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log()     { echo -e "${BLUE}[SETUP]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
dry()     { echo -e "${MAGENTA}[DRY-RUN]${NC} Would execute: $1"; }

# Progress tracking (managed in parent shell, exported for subshells)
COMPLETED_STEPS=0
FAILED_STEPS=0
SKIPPED_STEPS=0
CURRENT_STEP=0
TOTAL_STEPS=0
START_TIME=$(date +%s)

step_complete() {
    echo -e "\n${GREEN}[${CURRENT_STEP}/${TOTAL_STEPS}]${NC} $1"
}

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
                          workstation - Minimal + fonts, codecs, GNOME, desktop apps, power, drivers
                          dev         - Workstation + dev toolchains, editors, Docker, KVM/QEMU
                          gaming      - Workstation + Steam, Heroic, MangoHud, GameMode
                          creator     - Workstation + OBS Studio, v4l2loopback, wf-recorder, NV Broadcast
                          full        - Complete suite: Workstation + Dev + Gaming + Creator (default)
  --dev-type=GENRE      Choose developer genre for dev/full profile (comma-separated):
                          systems     - C, C++, Rust, CMake, Meson, GDB, Valgrind, ccache
                          web         - Node.js, Corepack (PNPM/Yarn), Python 3, jq
                          android     - ADB, Fastboot, Scrcpy, OpenJDK, Maven, Android Studio
                          ai          - Python Devel, Ruff, GPU Compute (CUDA / ROCm / Intel Compute)
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

# ==============================================================================
# Core Helper Functions
# ==============================================================================
run() {
    if $DRY_RUN; then
        dry "$*"
        return 0
    else
        "$@"
    fi
}

run_sudo() {
    if $DRY_RUN; then
        dry "sudo $*"
        return 0
    else
        sudo "$@"
    fi
}

is_gaming_profile() {
    [[ "$PROFILE" == "gaming" || "$PROFILE" == "full" ]]
}

is_creator_profile() {
    [[ "$PROFILE" == "creator" || "$PROFILE" == "full" ]]
}

is_dev_profile() {
    [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]
}

# Detect hardware once at startup so all functions can make hardware-aware decisions
detect_hardware() {
    local chassis
    chassis=$(hostnamectl chassis 2>/dev/null || echo "unknown")
    if [[ "$chassis" =~ ^(laptop|notebook|convertible|portable)$ ]] || compgen -G "/sys/class/power_supply/BAT*" > /dev/null; then
        IS_LAPTOP=true
    fi

    local gpu_info
    gpu_info=$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)
    if grep -qi nvidia <<< "$gpu_info"; then HAS_NVIDIA=true; fi
    if grep -Eqi 'amd|advanced micro devices|ati' <<< "$gpu_info"; then HAS_AMD=true; fi
    if grep -qi intel <<< "$gpu_info"; then HAS_INTEL=true; fi
}

# Get the user's configured login shell directly from /etc/passwd (updates immediately after chsh)
get_login_shell() {
    local target_user="${USER:-$(id -un)}"
    local passwd_shell
    passwd_shell=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f7 || true)
    basename "${passwd_shell:-${SHELL:-/bin/bash}}"
}

# Set or replace a configuration line in ~/.zshrc idempotently
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

prompt_input() {
    local prompt_text="$1" default_val="${2:-}" reply=""
    if $DRY_RUN || $UNATTENDED; then
        echo "$default_val"
        return 0
    fi
    read -r -p "$prompt_text" reply || reply=""
    echo "${reply:-$default_val}"
}

confirm() {
    local prompt="$1" default="${2:-N}" yn=""
    if $DRY_RUN; then
        dry "Prompt: $prompt (default: $default)"
        [[ "$default" == "Y" ]]
        return $?
    fi
    if $UNATTENDED; then
        info "$prompt -> Auto-${default} (unattended)"
        [[ "$default" == "Y" ]]
        return $?
    fi

    local suffix="(y/N)"
    [[ "$default" == "Y" ]] && suffix="(Y/n)"

    read -p "$prompt $suffix: " -n 1 -r yn || yn=""
    echo

    if [[ "$default" == "Y" ]]; then
        [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]]
    else
        [[ "$yn" =~ ^[Yy]$ ]]
    fi
}

verify_checksum() {
    local file="$1" expected="$2" actual
    if [[ ! -f "$file" ]]; then
        error "File not found for checksum verification: $file"
        return 1
    fi
    actual=$(sha256sum "$file" | cut -d' ' -f1)
    if [[ "$actual" != "$expected" ]]; then
        error "Checksum mismatch for $file (Expected: $expected, Actual: $actual)"
        return 1
    fi
    info "Checksum verified: $file"
    return 0
}

# Download a release asset from GitHub with progressive JSON parser fallback (jq -> python3 -> regex).
github_download() {
    local repo="$1" pattern="$2" output="$3" fallback="${4:-}" expected_sha256="${5:-}"
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local download_url="" api_response

    api_response=$(curl -sfL --max-time 10 "$api_url" 2>/dev/null || true)
    if [[ -n "$api_response" ]]; then
        if command -v jq &>/dev/null; then
            download_url=$(echo "$api_response" | jq -r ".assets[] | select(.name | test(\"$pattern\")) | .browser_download_url" 2>/dev/null | head -1 || true)
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

# Backup a file before modifying (preserves directory hierarchy)
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
            dry "Backup: $file -> $backup_path"
            return 0
        fi
        mkdir -p "$(dirname "$backup_path")" "$BACKUP_DIR"
        cp -p "$abs_file" "$backup_path"
        echo "$abs_file" >> "$BACKUP_DIR/.manifest"
        sort -u "$BACKUP_DIR/.manifest" -o "$BACKUP_DIR/.manifest"
        info "Backed up: $file -> $backup_path"
    fi
}

restore_backups() {
    local latest_backup
    # shellcheck disable=SC2012
    latest_backup=$(ls -td "$HOME/.config/fedora-setup-backups"/*/ 2>/dev/null | head -1 || true)
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
                mkdir -p "$(dirname "$orig")"
                cp "$backup_path" "$orig"
                success "Restored: $orig"
            fi
        done
    fi

    if ! $DRY_RUN; then
        rm -f "$STATE_FILE"
        warn "State reset due to restore - all steps will re-run on next execution"
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
        PROFILE="full"
        info "Auto-selected profile: $PROFILE"
        return 0
    fi

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}         Select Setup Profile           ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo "  1) minimal     - DNF, DNS, core CLI utilities, shell & terminal (4 steps)"
    echo "  2) workstation - Minimal + fonts, codecs, GNOME, desktop apps, power, drivers (11 steps)"
    echo "  3) dev         - Workstation + dev toolchains, editors, Docker, KVM/QEMU (15 steps)"
    echo "  4) gaming      - Workstation + Steam, Heroic, MangoHud, GameMode (12 steps)"
    echo "  5) creator     - Workstation + OBS Studio, v4l2loopback, wf-recorder, NV Broadcast (12 steps)"
    echo "  6) full        - Complete suite: Workstation + Dev + Gaming + Creator [default] (17 steps)"
    echo ""

    local choice
    choice=$(prompt_input "Enter choice [1-6, default: 6 (full)]: " "6")
    case "$choice" in
        1|minimal)     PROFILE="minimal" ;;
        2|workstation) PROFILE="workstation" ;;
        3|dev)         PROFILE="dev" ;;
        4|gaming)      PROFILE="gaming" ;;
        5|creator)     PROFILE="creator" ;;
        6|full|"")     PROFILE="full" ;;
        *)
            warn "Unrecognized selection '$choice'; defaulting to 'full' profile"
            PROFILE="full"
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
        echo "  4) ai      - Python Devel, Ruff, GPU Compute (CUDA / ROCm / Intel Compute)"
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
    ping -c 1 -W 2 1.1.1.1 &>/dev/null || ping -c 1 -W 2 8.8.8.8 &>/dev/null
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

# ==============================================================================
# Step 1: DNF Configuration & Core Repositories
# ==============================================================================
setup_dnf() {
    log "Configuring DNF5 & Third-Party Repositories..."

    backup_file "/etc/dnf/dnf.conf"

    if ! $DRY_RUN; then
        run_sudo sed -i '/^# BEGIN fedora-setup$/,/^# END fedora-setup$/d' /etc/dnf/dnf.conf
        run_sudo tee -a /etc/dnf/dnf.conf > /dev/null <<'EOF'
# BEGIN fedora-setup
max_parallel_downloads=10
defaultyes=True
# END fedora-setup
EOF
    else
        dry "Add max_parallel_downloads=10 and defaultyes=True block to /etc/dnf/dnf.conf"
    fi

    log "Enabling RPM Fusion (Free & Nonfree) and Flathub..."
    local fedora_ver
    fedora_ver=$(rpm -E %fedora 2>/dev/null || echo "44")
    [[ -z "$fedora_ver" || "$fedora_ver" == "%fedora" ]] && fedora_ver="44"

    run_sudo dnf install -y --setopt=best=True \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
    run_sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 2>/dev/null || true
    run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || warn "Flathub already configured or failed"

    run_sudo dnf upgrade -y --refresh --setopt=best=True

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

    step_complete "DNF & repositories configured"
}

# ==============================================================================
# Step 2: DNS Configuration
# ==============================================================================
setup_dns() {
    if $DRY_RUN; then
        dry "Configure custom DNS on active physical NetworkManager connections"
        step_complete "DNS (dry-run)"
        return 0
    fi

    echo ""
    log "DNS Configuration"
    info "Custom DNS replaces ISP resolvers with fast, privacy-respecting resolvers."
    info "Note: Skip if you use strict corporate VPNs or captive college portals."
    if ! confirm "Configure custom DNS resolvers?" "Y"; then
        info "Keeping default DHCP/ISP DNS settings"
        step_complete "DNS (skipped)"
        return 0
    fi

    echo "Choose a DNS provider:"
    echo "  1) Cloudflare DNS (1.1.1.1, 1.0.0.1) [default]"
    echo "  2) Google DNS (8.8.8.8, 8.8.4.4)"
    echo "  3) Quad9 Security DNS (9.9.9.9, 149.112.112.112)"
    echo "  4) Skip (keep current DNS)"

    local dns_choice DNS_IPV4 DNS_IPV6 DNS_NAME
    dns_choice=$(prompt_input "Select [1-4] (default: 1): " "1")

    case "$dns_choice" in
        2) DNS_IPV4="8.8.8.8 8.8.4.4"; DNS_IPV6="2001:4860:4860::8888 2001:4860:4860::8844"; DNS_NAME="Google" ;;
        3) DNS_IPV4="9.9.9.9 149.112.112.112"; DNS_IPV6="2620:fe::fe 2620:fe::9"; DNS_NAME="Quad9" ;;
        4) info "Keeping current DNS settings"; step_complete "DNS (skipped)"; return 0 ;;
        *) DNS_IPV4="1.1.1.1 1.0.0.1"; DNS_IPV6="2606:4700:4700::1111 2606:4700:4700::1001"; DNS_NAME="Cloudflare" ;;
    esac

    log "Applying $DNS_NAME DNS to active connections..."
    local conns
    conns=$(nmcli -t -f NAME connection show --active 2>/dev/null || true)
    while IFS= read -r conn; do
        [[ -z "$conn" ]] && continue
        if [[ "$conn" =~ ^(docker|lo|virbr|veth|br-|tailscale|wg) ]]; then
            info "Skipping virtual/tunnel interface: $conn"
            continue
        fi
        log "Setting DNS for: $conn"
        nmcli connection modify "$conn" ipv4.ignore-auto-dns yes ipv4.dns "$DNS_IPV4" 2>/dev/null || warn "Failed to set IPv4 DNS for $conn"
        nmcli connection modify "$conn" ipv6.ignore-auto-dns yes ipv6.dns "$DNS_IPV6" 2>/dev/null || warn "Failed to set IPv6 DNS for $conn"
        nmcli connection up "$conn" 2>/dev/null || warn "Failed to reload connection $conn"
    done <<< "$conns"

    step_complete "$DNS_NAME DNS configured"
}

# ==============================================================================
# Step 3: Core CLI Utilities
# ==============================================================================
setup_cli_core() {
    log "Installing essential CLI utilities..."

    local cli_pkgs=(
        fastfetch bat eza fd-find ripgrep fzf zoxide wget curl btop duf
        plocate tree compsize unzip unrar p7zip p7zip-plugins jq vim
        wl-clipboard xclip git android-tools
    )

    run_sudo dnf install -y --skip-unavailable "${cli_pkgs[@]}"

    step_complete "Core CLI utilities installed"
}

# ==============================================================================
# Step 4: Shell Environment, Starship & Terminal Emulator
# ==============================================================================
deploy_terminal_config() {
    local target="$1"

    case "$target" in
        ghostty)
            log "Deploying Ghostty Tokyo Night configuration..."
            if ! $DRY_RUN; then
                mkdir -p "$HOME/.config/ghostty"
                backup_file "$HOME/.config/ghostty/config"
                cat > "$HOME/.config/ghostty/config" <<'GHOSTTY_CONF'
theme = TokyoNight
font-family = FiraCode Nerd Font
font-family = Symbols Nerd Font Mono
font-size = 13
background-opacity = 0.90
background-blur = true
window-padding-x = 16
window-padding-y = 8,2
window-decoration = auto
confirm-close-surface = false
cursor-style = bar
cursor-style-blink = true
copy-on-select = clipboard
bell-features = no-audio
GHOSTTY_CONF
                success "Ghostty configuration deployed to ~/.config/ghostty/config"
            else
                dry "Deploy Ghostty Tokyo Night configuration to ~/.config/ghostty/config"
            fi
            ;;
        kitty)
            log "Deploying Kitty Tokyo Night configuration..."
            if ! $DRY_RUN; then
                mkdir -p "$HOME/.config/kitty"
                backup_file "$HOME/.config/kitty/kitty.conf"
                cat > "$HOME/.config/kitty/kitty.conf" <<'KITTY_CONF'
font_family      FiraCode Nerd Font
font_size        11.5
disable_ligatures never
background_opacity 0.95
window_padding_width 8 16 2
hide_window_decorations no
confirm_os_window_close 0
cursor_shape beam
copy_on_select clipboard
enable_audio_bell no

# Tokyo Night Color Scheme
background #1a1b26
foreground #c0caf5
selection_background #33467c
selection_foreground #c0caf5
url_color #73daca
cursor #c0caf5
cursor_text_color #1a1b26
active_tab_background #7aa2f7
active_tab_foreground #16161e
inactive_tab_background #24283b
inactive_tab_foreground #787c99
color0 #15161e
color1 #f7768e
color2 #9ece6a
color3 #e0af68
color4 #7aa2f7
color5 #bb9af7
color6 #7dcfff
color7 #a9b1d6
color8 #414868
color9 #f7768e
color10 #9ece6a
color11 #e0af68
color12 #7aa2f7
color13 #bb9af7
color14 #7dcfff
color15 #c0caf5
KITTY_CONF
                success "Kitty configuration deployed to ~/.config/kitty/kitty.conf"
            else
                dry "Deploy Kitty Tokyo Night configuration to ~/.config/kitty/kitty.conf"
            fi
            ;;
        alacritty)
            log "Deploying Alacritty Tokyo Night configuration..."
            if ! $DRY_RUN; then
                mkdir -p "$HOME/.config/alacritty"
                backup_file "$HOME/.config/alacritty/alacritty.toml"
                cat > "$HOME/.config/alacritty/alacritty.toml" <<'ALACRITTY_CONF'
[font]
size = 12.0

[font.normal]
family = "FiraCode Nerd Font"

[window]
opacity = 0.95
padding = { x = 12, y = 8 }

[colors.primary]
background = "#1a1b26"
foreground = "#c0caf5"

[colors.normal]
black = "#15161e"
red = "#f7768e"
green = "#9ece6a"
yellow = "#e0af68"
blue = "#7aa2f7"
magenta = "#bb9af7"
cyan = "#7dcfff"
white = "#a9b1d6"

[colors.bright]
black = "#414868"
red = "#f7768e"
green = "#9ece6a"
yellow = "#e0af68"
blue = "#7aa2f7"
magenta = "#bb9af7"
cyan = "#7dcfff"
white = "#c0caf5"
ALACRITTY_CONF
                success "Alacritty configuration deployed to ~/.config/alacritty/alacritty.toml"
            else
                dry "Deploy Alacritty Tokyo Night configuration to ~/.config/alacritty/alacritty.toml"
            fi
            ;;
    esac
}

setup_terminal() {
    log "Configuring GPU-Accelerated Terminal Emulator..."

    if confirm "Install a GPU-accelerated terminal emulator (Ghostty / Kitty / Alacritty)?" "Y"; then
        echo ""
        echo -e "${BLUE}Choose your terminal emulator:${NC}"
        echo -e "  ${GREEN}1) Ghostty (Recommended: Native GTK4/Wayland, fast GPU rendering, ligatures)${NC}"
        echo -e "  2) Kitty (Kitty graphics protocol, power-user splits)"
        echo -e "  3) Alacritty (Minimalist Rust OpenGL terminal)"
        echo ""

        local term_choice
        if $DRY_RUN; then
            term_choice="1"
            dry "Prompt user for Terminal Emulator selection: [1] Ghostty (Recommended), [2] Kitty, [3] Alacritty"
        else
            term_choice=$(prompt_input "Enter choice [1-3] (default: 1): " "1")
        fi

        case "$term_choice" in
            1)
                log "Installing Ghostty via Copr (scottames/ghostty)..."
                if ! $DRY_RUN; then
                    if run_sudo dnf copr enable -y scottames/ghostty; then
                        run_sudo dnf install -y --skip-unavailable ghostty || warn "Ghostty installation failed"
                    else
                        warn "Failed to enable Copr repository scottames/ghostty"
                    fi
                else
                    dry "Enable Copr repo scottames/ghostty and install ghostty via dnf"
                fi
                confirm "Apply Tokyo Night configuration for Ghostty?" "Y" && deploy_terminal_config "ghostty"
                ;;
            2)
                run_sudo dnf install -y --skip-unavailable kitty
                confirm "Apply Tokyo Night configuration for Kitty?" "Y" && deploy_terminal_config "kitty"
                ;;
            3)
                run_sudo dnf install -y --skip-unavailable alacritty
                confirm "Apply Tokyo Night configuration for Alacritty?" "Y" && deploy_terminal_config "alacritty"
                ;;
            *)
                info "Keeping stock Fedora terminal (Ptyxis)"
                ;;
        esac
    else
        info "Keeping stock Fedora terminal (Ptyxis)"
    fi
}

setup_shell() {
    log "Installing shell packages (Fish, ZSH)..."
    run_sudo dnf install -y --skip-unavailable zsh fish curl git fontconfig

    if ! $DRY_RUN; then
        mkdir -p "$HOME/.zsh/plugins"
        if [[ ! -d "$HOME/.zsh/plugins/zsh-autosuggestions" ]]; then
            run git clone --depth=1 --branch v0.7.1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/plugins/zsh-autosuggestions" 2>/dev/null || warn "Failed to clone zsh-autosuggestions"
        fi
        if [[ ! -d "$HOME/.zsh/plugins/zsh-syntax-highlighting" ]]; then
            run git clone --depth=1 --branch 0.8.0 https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.zsh/plugins/zsh-syntax-highlighting" 2>/dev/null || warn "Failed to clone zsh-syntax-highlighting"
        fi
    fi

    local selected_shell_name="Fish"
    local enable_dev_shell=false
    local install_starship=false

    if [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]; then
        echo ""
        info "Default Interactive Shell:"
        info "  1) Fish (Recommended: built-in autosuggestions, syntax highlighting & completions)"
        info "  2) ZSH (with autosuggestions & syntax highlighting)"
        info "  3) Bash"
        info "  4) Skip / Keep current shell ($(get_login_shell))"

        local shell_choice
        if $DRY_RUN; then
            shell_choice="1"
            dry "Prompt user for default shell selection: [1] Fish (Recommended), [2] ZSH, [3] Bash, [4] Skip (default: 1)"
        else
            shell_choice=$(prompt_input "Enter choice [1-4] (default: 1): " "1")
        fi

        case "$shell_choice" in
            1)
                selected_shell_name="Fish"
                if ! $DRY_RUN && command -v fish &>/dev/null; then
                    local fish_bin
                    fish_bin=$(command -v fish)
                    grep -qxF "$fish_bin" /etc/shells || echo "$fish_bin" | run_sudo tee -a /etc/shells >/dev/null
                    run_sudo chsh -s "$fish_bin" "${USER:-$(id -un)}" 2>/dev/null || warn "Failed to set login shell to Fish"
                    success "Default login shell set to Fish"
                else
                    dry "Set default login shell to Fish via chsh"
                fi
                ;;
            2)
                selected_shell_name="ZSH"
                if ! $DRY_RUN && command -v zsh &>/dev/null; then
                    local zsh_bin
                    zsh_bin=$(command -v zsh)
                    grep -qxF "$zsh_bin" /etc/shells || echo "$zsh_bin" | run_sudo tee -a /etc/shells >/dev/null
                    run_sudo chsh -s "$zsh_bin" "${USER:-$(id -un)}" 2>/dev/null || warn "Failed to set login shell to ZSH"
                    success "Default login shell set to ZSH"
                else
                    dry "Set default login shell to ZSH via chsh"
                fi
                ;;
            3)
                selected_shell_name="Bash"
                if ! $DRY_RUN; then
                    run_sudo chsh -s /bin/bash "${USER:-$(id -un)}" 2>/dev/null || warn "Failed to set login shell to Bash"
                    success "Default login shell set to Bash"
                else
                    dry "Set default login shell to Bash via chsh"
                fi
                ;;
            *)
                info "Keeping current login shell ($(get_login_shell))"
                ;;
        esac

        # Developer Environment & Aliases Configuration
        echo ""
        info "Developer Environment & Aliases Configuration for $selected_shell_name:"
        info "  1) Developer environment exports & full aliases (Neovim, Git shortcuts, toolchains, pager overrides) [Recommended]"
        info "  2) Clean standard aliases only (clear, ls, cat, less without dev exports)"

        local dev_env_choice
        if $DRY_RUN; then
            dev_env_choice="1"
            dry "Prompt for developer environment & aliases configuration for $selected_shell_name: [1] Full developer environment, [2] Clean standard aliases only (default: 1)"
        else
            dev_env_choice=$(prompt_input "Enter choice [1-2] (default: 1): " "1")
        fi

        case "$dev_env_choice" in
            1|y|Y)
                enable_dev_shell=true
                info "Enabling developer environment exports and aliases for $selected_shell_name"
                ;;
            *)
                enable_dev_shell=false
                info "Configuring clean standard aliases only for $selected_shell_name"
                ;;
        esac

        # Starship Cross-Shell Prompt:
        if [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]; then
            if confirm "Install and configure Starship prompt?" "Y"; then
                install_starship=true
            fi
        fi
    else
        enable_dev_shell=false
        if $DRY_RUN; then
            dry "Deploy Fish clean standard aliases"
            dry "Deploy ZSH clean standard aliases"
            dry "Deploy Bash clean standard aliases"
        fi
    fi

    if $install_starship; then
        if ! command -v starship &>/dev/null && ! $DRY_RUN; then
            if ! run_sudo dnf install -y --skip-unavailable starship 2>/dev/null; then
                log "Installing Starship via official installer..."
                local starship_installer
                starship_installer=$(mktemp /tmp/starship-install-XXXXXX.sh)
                if curl --proto '=https' --tlsv1.2 -fsSL https://starship.rs/install.sh -o "$starship_installer"; then
                    sh "$starship_installer" -y >/dev/null 2>&1 || warn "Starship installer failed"
                fi
                rm -f "$starship_installer"
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
Fedora = "󰣛 "
Linux = "󰌽 "
Ubuntu = " "
Debian = " "
Arch = "󰣇 "

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

[git_branch]
symbol = " "
style = "bold purple"
format = "on [$symbol$branch]($style) "

[git_status]
style = "bold red"
format = '([\[$all_status$ahead_behind\]]($style) )'

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
symbol = " "
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
STARSHIP_CONFIG
            success "Starship prompt configuration deployed (~/.config/starship.toml)"
        else
            dry "Deploy Starship prompt configuration to ~/.config/starship.toml"
        fi
    fi

    # Deploy ZSH configuration (~/.zshrc)
    if ! $DRY_RUN; then
        backup_file "$HOME/.zshrc"
        cat > "$HOME/.zshrc" <<'ZSHRC_BASE'
# ===== Zsh History =====
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

setopt APPEND_HISTORY SHARE_HISTORY INC_APPEND_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

bindkey '^[[;5D' backward-word
bindkey '^[[;5C' forward-word
bindkey '^L' clear-screen

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#8a8a8a"
[[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# ===== Standard Aliases =====
alias clear='printf "\033[2J\033[3J\033[H"'
alias ls='eza --group-directories-first --classify --icons --git'
alias la='ls -la'
alias cat='bat --paging=never --style=plain'
alias less='bat --paging=always --pager="less -R"'
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
ZSHRC_BASE

        if $enable_dev_shell; then
            cat >> "$HOME/.zshrc" <<'ZSHRC_DEV'

# ===== Developer Environment & Git Shortcuts =====
export EDITOR=nvim
export VISUAL=nvim
export PAGER=cat
export SYSTEMD_PAGER=cat
export MANPAGER=cat
export DELTA_PAGER=cat
export LESS="-F -X -R"
export LIBVIRT_DEFAULT_URI="qemu:///system"

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
ZSHRC_DEV
        fi

        if $install_starship; then
            cat >> "$HOME/.zshrc" <<'ZSHRC_STARSHIP'
command -v starship >/dev/null && eval "$(starship init zsh)"
ZSHRC_STARSHIP
        fi
    else
        dry "Deploy ~/.zshrc configuration"
    fi

    # Deploy Bash configuration (~/.bashrc)
    if ! $DRY_RUN; then
        backup_file "$HOME/.bashrc"
        sed -i '/# >>> FEDORA_POST_INSTALL_MANAGED >>>/,/# <<< FEDORA_POST_INSTALL_MANAGED <<</d' "$HOME/.bashrc" 2>/dev/null || true

        cat >> "$HOME/.bashrc" <<'BASHRC_BASE'
# >>> FEDORA_POST_INSTALL_MANAGED >>>
alias clear='printf "\033[2J\033[3J\033[H"'
alias ls='eza --group-directories-first --classify --icons --git'
alias la='ls -la'
alias cat='bat --paging=never --style=plain'
alias less='bat --paging=always --pager="less -R"'
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
BASHRC_BASE

        if $enable_dev_shell; then
            cat >> "$HOME/.bashrc" <<'BASHRC_DEV'
export EDITOR=nvim
export VISUAL=nvim
export PAGER=cat
export SYSTEMD_PAGER=cat
export MANPAGER=cat
export LESS="-F -X -R"
export LIBVIRT_DEFAULT_URI="qemu:///system"

alias gs='git status -sb'
alias ga='git add'
alias gaa='git add -A'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gpl='git pull --rebase'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -n 15'
BASHRC_DEV
        fi

        if $install_starship; then
            cat >> "$HOME/.bashrc" <<'BASHRC_STARSHIP'
command -v starship >/dev/null && eval "$(starship init bash)"
BASHRC_STARSHIP
        fi
        echo "# <<< FEDORA_POST_INSTALL_MANAGED <<<" >> "$HOME/.bashrc"
    else
        dry "Update ~/.bashrc managed block"
    fi

    # Deploy Fish configuration (~/.config/fish/config.fish)
    if ! $DRY_RUN; then
        mkdir -p "$HOME/.config/fish"
        backup_file "$HOME/.config/fish/config.fish"
        cat > "$HOME/.config/fish/config.fish" <<'FISH_BASE'
set -g fish_greeting ""
set -g fish_color_autosuggestion 828bb8
fish_add_path -m $HOME/.local/bin $HOME/.cargo/bin

alias clear 'printf "\033[2J\033[3J\033[H"'
alias ls 'eza --group-directories-first --classify --icons --git'
alias la 'ls -la'
alias cat 'bat --paging=never --style=plain'
alias less 'bat --paging=always --pager="less -R"'

if type -q fzf
    fzf --fish | source
end
FISH_BASE

        if $enable_dev_shell; then
            cat >> "$HOME/.config/fish/config.fish" <<'FISH_DEV'

set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx PAGER cat
set -gx SYSTEMD_PAGER cat
set -gx MANPAGER cat
set -gx LESS "-F -X -R"
set -gx LIBVIRT_DEFAULT_URI "qemu:///system"

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
FISH_DEV
        fi

        if $install_starship; then
            cat >> "$HOME/.config/fish/config.fish" <<'FISH_STARSHIP'

if type -q starship
    starship init fish | source
end
FISH_STARSHIP
        fi
        success "Shell configurations deployed (.zshrc, .bashrc, config.fish)"
    else
        dry "Deploy ~/.config/fish/config.fish"
    fi

    # Terminal emulator configuration (strictly dev and full profiles)
    if is_dev_profile; then
        setup_terminal
    fi

    step_complete "Shell & terminal configured"
}

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

# ==============================================================================
# Step 6: Multimedia Codecs & PipeWire/WirePlumber Audio
# ==============================================================================
setup_multimedia() {
    log "Configuring multimedia codecs, hardware VA-API, and PipeWire audio..."

    run_sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    run_sudo dnf install -y --allowerasing \
        gstreamer1-plugins-bad-freeworld \
        gstreamer1-plugins-ugly \
        gstreamer1-plugin-openh264 \
        mozilla-openh264 \
        libva-utils 2>/dev/null || warn "Some multimedia packages failed to install"

    run_sudo dnf group install -y --with-optional multimedia --setopt=install_weak_deps=False -x PackageKit-gstreamer-plugin 2>/dev/null || \
        warn "Multimedia group install had partial warnings (non-critical)"

    log "Configuring WirePlumber Bluetooth HD audio & PipeWire dynamic sample rates..."
    if ! $DRY_RUN; then
        run_sudo mkdir -p /etc/wireplumber/wireplumber.conf.d /etc/pipewire/pipewire.conf.d
        run_sudo tee /etc/wireplumber/wireplumber.conf.d/50-bluez.conf > /dev/null <<'BLUEZ_CONF'
monitor.bluez.properties = {
  bluez5.roles = [ a2dp_sink a2dp_source hfp_hf hfp_ag ]
  bluez5.codecs = [ ldac aac aptx_hd aptx sbc_xq sbc ]
  bluez5.enable-sbc-xq = true
  bluez5.enable-msbc = true
  bluez5.enable-hw-volume = true
}

wireplumber.settings = {
  bluetooth.autoswitch-to-headset-profile = false
}
BLUEZ_CONF

        # Prevent GDM from hijacking Bluetooth headphones before user login
        if id gdm &>/dev/null; then
            run_sudo mkdir -p /var/lib/gdm/.config/wireplumber/wireplumber.conf.d
            run_sudo tee /var/lib/gdm/.config/wireplumber/wireplumber.conf.d/disable-bluetooth.conf > /dev/null <<'GDM_BT_CONF'
wireplumber.profiles = {
  main = {
    hardware.bluetooth = disabled
  }
}
GDM_BT_CONF
            run_sudo chown -R gdm:gdm /var/lib/gdm/.config/wireplumber 2>/dev/null || true
        fi

        run_sudo tee /etc/pipewire/pipewire.conf.d/99-clock-rates.conf > /dev/null <<'CLOCK_CONF'
context.properties = {
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]
}
CLOCK_CONF

        if systemctl --user is-active wireplumber &>/dev/null; then
            systemctl --user restart pipewire wireplumber 2>/dev/null || true
        fi
        success "PipeWire dynamic sample rates & WirePlumber Bluetooth HD audio configured"
    else
        dry "Deploy WirePlumber Bluetooth HD config and PipeWire dynamic clock rate config"
    fi

    step_complete "Multimedia & audio configured"
}

# ==============================================================================
# Step 7: GNOME Desktop Tweaks & Extensions
# ==============================================================================
setup_gnome() {
    log "Configuring GNOME Tweaks, GSConnect & Mutter optimizations..."
    run_sudo dnf install -y gnome-tweaks gnome-shell-extension-gsconnect gnome-shell-extension-appindicator

    if command -v firewall-cmd &>/dev/null && ! $DRY_RUN; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            run_sudo firewall-cmd --permanent --add-service=kdeconnect 2>/dev/null || true
            run_sudo firewall-cmd --reload 2>/dev/null || true
            success "Firewall port opened for GSConnect / KDE Connect"
        fi
    fi

    if confirm "Apply transparent GTK3/GTK4 titlebar CSS?" "Y"; then
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
        success "GNOME Mutter check-alive-timeout set to 0"
    fi

    step_complete "GNOME desktop configured"
}

# ==============================================================================
# Step 8: Desktop Applications (Browser, Media, Flatpaks, Productivity)
# ==============================================================================
setup_desktop_apps() {
    log "Installing Brave Browser & desktop productivity applications..."

    run_sudo dnf install -y dnf-plugins-core
    run_sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo --overwrite 2>/dev/null || warn "Failed to add Brave repository"
    run_sudo dnf install -y --skip-unavailable \
        brave-browser vlc qbittorrent telegram-desktop timeshift gparted ntfs-3g wmctrl

    log "Installing essential Flatpaks (LocalSend, Extension Manager)..."
    run flatpak install -y flathub org.localsend.localsend_app com.mattjakeman.ExtensionManager 2>/dev/null || warn "Flatpak installation had warnings"

    # Yazi Terminal File Manager (COPR)
    if confirm "Install Yazi (blazing-fast Rust terminal file manager with media previews)?" "Y"; then
        if run_sudo dnf copr enable -y lihaohong/yazi; then
            run_sudo dnf install -y --skip-unavailable yazi file poppler-utils resvg ImageMagick || warn "Yazi install had warnings"
        fi
    fi

    # Vesktop (Architecture-aware download)
    if confirm "Install Vesktop (Discord client with Vencord & Wayland audio sharing)?" "Y"; then
        if ! $DRY_RUN; then
            local fallback_url="https://github.com/Vencord/Vesktop/releases/latest/download/vesktop.${SYS_ARCH}.rpm"
            if github_download "Vencord/Vesktop" "vesktop.*\.${SYS_ARCH}\.rpm" "/tmp/vesktop.rpm" "$fallback_url"; then
                run_sudo dnf install -y /tmp/vesktop.rpm 2>/dev/null || warn "Vesktop RPM install failed"
                rm -f /tmp/vesktop.rpm
            else
                warn "Could not download Vesktop RPM for $SYS_ARCH"
            fi
        else
            dry "Download and install Vesktop RPM ($SYS_ARCH)"
        fi
    fi

    # Stirling-PDF
    if ! command -v stirling-pdf &>/dev/null && ! rpm -q stirling-pdf &>/dev/null; then
        if confirm "Install Stirling-PDF (offline desktop PDF toolkit)?" "N"; then
            if ! $DRY_RUN; then
                local stirling_rpm="/tmp/stirling-pdf.rpm"
                if github_download "Stirling-Tools/Stirling-PDF" "Stirling-PDF-linux-${SYS_ARCH}\.rpm" "$stirling_rpm" \
                    "https://files.stirlingpdf.com/linux-installer.rpm"; then
                    run_sudo dnf install -y "$stirling_rpm" 2>/dev/null || warn "Stirling-PDF install failed"
                    rm -f "$stirling_rpm"
                fi
            else
                dry "Download and install Stirling-PDF RPM"
            fi
        fi
    fi

    step_complete "Desktop applications installed"
}

# ==============================================================================
# Step 9: Hardware-Aware Power & Sleep Management
# ==============================================================================
setup_power() {
    log "Configuring Power & Sleep policies..."

    if $IS_LAPTOP; then
        info "Laptop chassis detected."
        info "Modern AMD/Intel laptops perform best with Fedora's default power daemon (tuned-ppd / power-profiles-daemon)."
        if confirm "Replace default GNOME power profiles with TLP anyway?" "N"; then
            run_sudo dnf install -y tlp tlp-rdw
            run_sudo systemctl mask power-profiles-daemon.service 2>/dev/null || true
            run_sudo systemctl enable --now tlp.service
            success "TLP enabled"
        else
            info "Keeping native Fedora power profile management"
        fi
    else
        info "Desktop chassis detected: Skipping laptop battery daemon (TLP)."
    fi

    # Safe No-Sleep: Disable auto-sleep on AC power, but protect laptops on battery power!
    if confirm "Disable auto-suspend when plugged into AC power?" "Y"; then
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
EOF
            run_sudo dconf update 2>/dev/null || true

            gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 2>/dev/null || true
            gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
            success "AC auto-suspend disabled (battery suspend preserved for safety)"
        else
            dry "Disable AC auto-suspend in GDM dconf and user gsettings"
        fi
    fi

    # High-Performance ZRAM & Kernel Memory Tuning (up to 16GB zstd)
    if confirm "Apply high-performance ZRAM memory tuning (zstd compression, swappiness 100)?" "Y"; then
        if ! $DRY_RUN; then
            run_sudo mkdir -p /etc/systemd /etc/sysctl.d
            run_sudo tee /etc/systemd/zram-generator.conf > /dev/null <<'ZRAM_EOF'
[zram0]
zram-size = min(ram, 16384)
compression-algorithm = zstd
ZRAM_EOF

            run_sudo tee /etc/sysctl.d/99-zram.conf > /dev/null <<'SYSCTL_EOF'
vm.swappiness = 100
vm.page-cluster = 0
SYSCTL_EOF

            run_sudo sysctl --system >/dev/null 2>&1 || true
            run_sudo swapoff /dev/zram0 2>/dev/null || true
            run_sudo systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
            success "High-performance ZRAM tuning applied (/etc/systemd/zram-generator.conf)"
        else
            dry "Configure /etc/systemd/zram-generator.conf (zstd, 16GB max) and /etc/sysctl.d/99-zram.conf"
        fi
    fi

    step_complete "Power & sleep policies configured"
}

# ==============================================================================
# Step 10: Modular Development Toolchains
# ==============================================================================
setup_dev() {
    log "Configuring modular development stack..."

    local selected_genres=()
    if [[ -n "${DEV_TYPE:-}" && "$DEV_TYPE" != "all" ]]; then
        IFS=',' read -ra selected_genres <<< "$DEV_TYPE"
    else
        selected_genres=("systems" "web" "android" "ai")
    fi

    has_dev_genre() {
        local target="$1"
        for g in "${selected_genres[@]}"; do
            [[ "$g" == "$target" || "$g" == "all" ]] && return 0
        done
        return 1
    }

    # Lean baseline packages shared across all developers
    local dev_pkgs=(
        git-lfs git-filter-repo gnupg rsync zip lz4
        openssl-devel zlib-devel pkgconf-pkg-config
        glab gh neovim
    )
    run_sudo dnf install -y --skip-unavailable "${dev_pkgs[@]}"

    if [[ "$PROFILE" == "full" ]]; then
        local full_dev_pkgs=(
            dpkg-dev
            copr-cli
            osc
            python3-keyring
            libX11-devel
            libxkbcommon-x11-devel
            libxcb-devel
            fontconfig-devel
            alsa-lib-devel
        )
        run_sudo dnf install -y --skip-unavailable "${full_dev_pkgs[@]}"
    fi

    # 1. Systems & Low-Level Genre
    # ccache (Fast C/C++ Compiler Cache):
    if has_dev_genre "systems"; then
        log "Installing Systems & Low-Level toolchain (C/C++, Debuggers, Profilers)..."
        local sys_pkgs=(
            gcc gcc-c++ clang llvm lld make cmake meson ninja-build
            automake autoconf libtool bear gdb valgrind strace ltrace
            clang-tools-extra bc bison flex protobuf-compiler
            elfutils-libelf-devel elfutils-devel gnutls-devel hyperfine
        )
        run_sudo dnf install -y --skip-unavailable "${sys_pkgs[@]}"

        echo ""
        info "Rust Toolchain Installation Method:"
        info "  1) rustup (Recommended: official toolchain manager for stable/nightly/targets)"
        info "  2) Fedora system RPMs (rust, cargo, clippy, rustfmt, rust-analyzer)"
        info "  3) Skip Rust"
        local rust_choice
        rust_choice=$(prompt_input "Select [1-3] (default: 1): " "1")
        case "$rust_choice" in
            1)
                run_sudo dnf install -y rustup
                if ! $DRY_RUN && [[ ! -f "$HOME/.cargo/bin/rustc" ]]; then
                    rustup-init -y --no-modify-path --default-toolchain stable
                    "$HOME/.cargo/bin/rustup" component add clippy rustfmt rust-analyzer
                    success "Rust toolchain initialized via rustup"
                else
                    dry "Initialize rustup stable toolchain with clippy, rustfmt, rust-analyzer"
                fi
                ;;
            2)
                run_sudo dnf install -y rust cargo clippy rustfmt rust-analyzer
                ;;
            *) info "Skipping Rust installation" ;;
        esac

        if confirm "Install and configure ccache (50GB compressed compiler cache)?" "Y"; then
            run_sudo dnf install -y --skip-unavailable ccache
            if ! $DRY_RUN; then
                mkdir -p "$HOME/.ccache"
                ccache --set-config=cache_dir="$HOME/.ccache" 2>/dev/null || true
                ccache --set-config=max_size=50G 2>/dev/null || true
                ccache --set-config=compression=true 2>/dev/null || true
                success "ccache configured (50GB limit)"
            else
                dry "Configure ccache: 50GB max size, compression enabled"
            fi
        fi
    fi

    # 2. Web & Cloud Genre
    if has_dev_genre "web"; then
        log "Installing Web & Cloud toolchain (Node.js, Corepack, Python)..."
        run_sudo dnf install -y --skip-unavailable nodejs nodejs-corepack python3 python3-pip jq
        if ! $DRY_RUN && command -v corepack &>/dev/null; then
            mkdir -p "$HOME/.local/bin"
            corepack enable --install-directory "$HOME/.local/bin" 2>/dev/null || warn "Corepack enable had warnings"
            success "Corepack (pnpm/yarn) enabled in ~/.local/bin"
        fi
    fi

    # 3. Android & Mobile Genre
    if has_dev_genre "android"; then
        log "Installing Android & Java toolchain..."
        run_sudo dnf install -y --skip-unavailable android-tools java-latest-openjdk java-latest-openjdk-devel maven

        if confirm "Install Scrcpy (low-latency Android screen mirroring via COPR)?" "Y"; then
            if run_sudo dnf copr enable -y zeno/scrcpy; then
                run_sudo dnf install -y --skip-unavailable scrcpy || warn "Scrcpy install failed"
            fi
        fi

        if confirm "Install Android Studio (via Flathub)?" "N"; then
            run flatpak install -y flathub com.google.AndroidStudio 2>/dev/null || warn "Android Studio Flatpak failed"
        fi
    fi

    # 4. Data & AI Genre (Multi-vendor GPU Compute: NVIDIA CUDA / AMD ROCm / Intel Compute)
    if has_dev_genre "ai"; then
        log "Installing Data & AI stack (Python Devel, Ruff, UV, GPU Compute)..."
        run_sudo dnf install -y --skip-unavailable python3-devel python3-virtualenv python3-wheel python3-setuptools ruff uv

        if $HAS_NVIDIA; then
            if confirm "NVIDIA GPU detected: Install CUDA development toolkit?" "Y"; then
                run_sudo dnf install -y --skip-unavailable xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-cuda-devel
            fi
        fi

        # Offer ROCm only if AMD is a discrete GPU or primary accelerator (avoids unworkable installs on mobile APUs)
        if $HAS_AMD && { ! $HAS_NVIDIA || lspci 2>/dev/null | grep -Ei 'VGA|3D' | grep -i amd | grep -qi 'Navi\|Radeon RX\|Discrete'; }; then
            if confirm "AMD Radeon discrete GPU detected: Install ROCm HIP & OpenCL compute runtime?" "N"; then
                run_sudo dnf install -y --skip-unavailable rocm-hip rocm-opencl rocm-clinfo rocm-smi
            fi
        fi

        if $HAS_INTEL; then
            if confirm "Intel GPU detected: Install Intel Compute Runtime (Level Zero / OpenCL)?" "Y"; then
                run_sudo dnf install -y --skip-unavailable intel-compute-runtime oneapi-level-zero
            fi
        fi
    fi

    # Configure Python symlinks & Git sensible defaults
    if ! $DRY_RUN; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v python3 || echo /usr/bin/python3)" "$HOME/.local/bin/python" 2>/dev/null || true
        git config --global core.pager cat 2>/dev/null || true
        git config --global push.autoSetupRemote true 2>/dev/null || true
        git config --global pull.rebase true 2>/dev/null || true
        git config --global diff.colorMoved zebra 2>/dev/null || true
    fi

    # Architecture-Aware PostgreSQL Server
    if confirm "Install and initialize PostgreSQL Server?" "N"; then
        if ! $DRY_RUN; then
            if [[ "$SYS_ARCH" == "x86_64" ]]; then
                local fedora_ver
                fedora_ver=$(rpm -E %fedora 2>/dev/null || echo "44")
                local pgdg_rpm="https://download.postgresql.org/pub/repos/yum/reporpms/F-${fedora_ver}-${SYS_ARCH}/pgdg-fedora-repo-latest.noarch.rpm"
                rpm -q pgdg-fedora-repo &>/dev/null || run_sudo dnf install -y --skip-unavailable "$pgdg_rpm"
                if run_sudo dnf install -y postgresql18-server postgresql18; then
                    [[ -f "/var/lib/pgsql/18/data/PG_VERSION" ]] || run_sudo /usr/pgsql-18/bin/postgresql-18-setup initdb
                    run_sudo systemctl enable --now postgresql-18
                    success "PostgreSQL 18 (PGDG) initialized and running"
                fi
            else
                info "Architecture is $SYS_ARCH: Installing PostgreSQL from standard Fedora repositories..."
                if run_sudo dnf install -y postgresql-server postgresql; then
                    run_sudo postgresql-setup --initdb 2>/dev/null || true
                    run_sudo systemctl enable --now postgresql
                    success "PostgreSQL initialized and running"
                fi
            fi
        else
            dry "Install and initialize PostgreSQL Server"
        fi
    fi

    step_complete "Development toolchains configured"
}

# ==============================================================================
# Step 11: Code Editor Selection & Shell-Aware Configuration
# ==============================================================================
setup_editor() {
    log "Configuring Code Editor..."

    local active_shell
    active_shell=$(get_login_shell)

    echo ""
    echo -e "${BLUE}Choose your primary code editor:${NC}"
    echo -e "  ${GREEN}1) Zed (Recommended: High-performance Rust editor)${NC}"
    echo -e "  2) VS Codium (Telemetry-free VS Code binary)"
    echo -e "  3) Google Antigravity IDE"
    echo -e "  ${YELLOW}4) VS Code (Microsoft build)${NC}"
    echo -e "  5) Skip editor installation"
    echo ""

    local editor_choice
    editor_choice=$(prompt_input "Enter choice [1-5] (default: 1): " "1")

    case "$editor_choice" in
        1)
            log "Installing and configuring Zed Editor..."
            if ! $DRY_RUN; then
                if ! command -v zed &>/dev/null; then
                    if ! run_sudo dnf install -y --skip-unavailable zed 2>/dev/null; then
                        local zed_installer
                        zed_installer=$(mktemp /tmp/zed-install-XXXXXX.sh)
                        if curl --proto '=https' --tlsv1.2 -fsSL https://zed.dev/install.sh -o "$zed_installer"; then
                            bash "$zed_installer" 2>/dev/null || warn "Zed script install failed"
                        fi
                        rm -f "$zed_installer"
                    fi
                fi

                mkdir -p "$HOME/.config/zed" "$HOME/.local/bin"
                backup_file "$HOME/.config/zed/settings.json"
                cat > "$HOME/.config/zed/settings.json" <<'ZED_SETTINGS'
{
  "agent": {
    "sidebar_side": "right"
  },
  "project_panel": {
    "dock": "left"
  },
  "icon_theme": "Catppuccin Mocha",
  "terminal": {
    "font_size": 14.0,
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
  "buffer_font_family": "FiraCode Nerd Font",
  "base_keymap": "VSCode",
  "ui_font_size": 15,
  "buffer_font_size": 15.0,
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
LOGIN_SH="$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)"
LOGIN_SH="${LOGIN_SH:-${SHELL:-/bin/bash}}"

if [[ -z "$FILE" ]]; then
    echo "[Zed Runner] No file provided."
    exec "$LOGIN_SH"
fi

EXT="${FILE##*.}"
DIR="$(dirname "$FILE")"
NAME="$(basename "$FILE")"
BASE="${NAME%.*}"

drop_to_shell() {
    echo -e "\n\033[1;33m[Interrupted. Interactive shell active:]\033[0m"
    exec "$LOGIN_SH"
}
trap drop_to_shell INT TERM

echo -e "\033[1;34m==>\033[0m \033[1;32mRunning:\033[0m $NAME"
cd "$DIR" || exit 1

case "$EXT" in
    py)  python3 "$FILE" ;;
    rs)
        if [[ -f "Cargo.toml" || -f "../Cargo.toml" ]]; then
            cargo run
        else
            rustc "$FILE" -o "/tmp/$BASE" && "/tmp/$BASE"
        fi
        ;;
    c)   gcc -O2 "$FILE" -o "/tmp/$BASE" -lm && "/tmp/$BASE" ;;
    cpp|cc|cxx) g++ -O2 "$FILE" -o "/tmp/$BASE" && "/tmp/$BASE" ;;
    go)  go run "$FILE" ;;
    js)  node "$FILE" ;;
    ts)  npx tsx "$FILE" 2>/dev/null || npx ts-node "$FILE" ;;
    sh|bash) bash "$FILE" ;;
    *)   echo "[Zed Runner] Unsupported file extension: .$EXT" ;;
esac

echo -e "\n\033[1;36m[Finished. Interactive shell active:]\033[0m"
exec "$LOGIN_SH"
ZED_RUN
                chmod +x "$HOME/.local/bin/zed-run"
                success "Zed Editor installed and configured"
            else
                dry "Install Zed Editor and deploy configuration"
            fi
            ;;

        2)
            log "Installing VS Codium..."
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
                run_sudo dnf install -y codium || warn "Failed to install VSCodium"
                mkdir -p "$HOME/.config/VSCodium/User"
                backup_file "$HOME/.config/VSCodium/User/settings.json"
                cat > "$HOME/.config/VSCodium/User/settings.json" <<EOF
{
    "editor.fontFamily": "'FiraCode Nerd Font', 'Fira Code', monospace",
    "editor.fontWeight": "500",
    "editor.fontLigatures": true,
    "editor.fontSize": 14,
    "terminal.integrated.fontFamily": "'FiraCode Nerd Font', monospace",
    "terminal.integrated.fontSize": 14,
    "terminal.integrated.defaultProfile.linux": "$active_shell",
    "files.autoSave": "afterDelay"
}
EOF
                success "VS Codium installed and configured for $active_shell"
            else
                dry "Install VSCodium and configure settings.json"
            fi
            ;;

        3)
            log "Installing Google Antigravity IDE..."
            if ! $DRY_RUN; then
                if ! command -v agy &>/dev/null; then
                    local agy_installer
                    agy_installer=$(mktemp /tmp/agy-install-XXXXXX.sh)
                    if curl --proto '=https' --tlsv1.2 -fsSL https://antigravity.google/cli/install.sh -o "$agy_installer"; then
                        bash "$agy_installer" 2>/dev/null || warn "Antigravity install failed"
                    fi
                    rm -f "$agy_installer"
                fi
                mkdir -p "$HOME/.config/antigravity"
                backup_file "$HOME/.config/antigravity/settings.json"
                cat > "$HOME/.config/antigravity/settings.json" <<EOF
{
    "editor.fontFamily": "'FiraCode Nerd Font', 'Fira Code', monospace",
    "editor.fontLigatures": true,
    "editor.fontSize": 14,
    "terminal.integrated.fontFamily": "'FiraCode Nerd Font', monospace",
    "terminal.integrated.defaultProfile.linux": "$active_shell",
    "files.autoSave": "afterDelay"
}
EOF
                success "Antigravity IDE configured (without overwriting VS Code/VSCodium configs)"
            else
                dry "Install Antigravity IDE and deploy ~/.config/antigravity/settings.json"
            fi
            ;;

        4)
            log "Installing Visual Studio Code..."
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
                run_sudo dnf install -y code || warn "Failed to install VS Code"
                mkdir -p "$HOME/.config/Code/User"
                backup_file "$HOME/.config/Code/User/settings.json"
                cat > "$HOME/.config/Code/User/settings.json" <<EOF
{
    "editor.fontFamily": "'FiraCode Nerd Font', 'Fira Code', monospace",
    "editor.fontLigatures": true,
    "editor.fontSize": 14,
    "terminal.integrated.fontFamily": "'FiraCode Nerd Font', monospace",
    "terminal.integrated.defaultProfile.linux": "$active_shell",
    "files.autoSave": "afterDelay"
}
EOF
                success "VS Code installed and configured for $active_shell"
            else
                dry "Install VS Code and configure settings.json"
            fi
            ;;

        *)
            info "Skipped code editor installation"
            ;;
    esac

    step_complete "Code editor configured"
}

# ==============================================================================
# Step 12: Docker & Compose Setup
# ==============================================================================
setup_docker() {
    log "Configuring Docker Engine & Compose..."

    run_sudo dnf install -y --skip-unavailable moby-engine docker-cli containerd docker-compose

    if ! rpm -q moby-engine &>/dev/null && ! rpm -q docker-ce &>/dev/null; then
        warn "Docker engine package not found - skipping daemon configuration"
        step_complete "Docker (skipped)"
        return 0
    fi

    # Tell NetworkManager to ignore docker0 to prevent route metric conflicts
    if ! $DRY_RUN && [[ ! -f /etc/NetworkManager/conf.d/10-docker.conf ]]; then
        run_sudo mkdir -p /etc/NetworkManager/conf.d
        run_sudo tee /etc/NetworkManager/conf.d/10-docker.conf >/dev/null <<'EOF'
[keyfile]
unmanaged-devices=interface-name:docker0
EOF
        run_sudo systemctl reload NetworkManager 2>/dev/null || true
    fi

    run_sudo usermod -aG docker "${USER:-$(id -un)}"
    run_sudo systemctl enable --now containerd.service docker.service 2>/dev/null || warn "Failed to start Docker daemon"

    # Architecture-aware Docker Compose CLI plugin fallback if RPM plugin isn't present
    if ! docker compose version &>/dev/null && ! $DRY_RUN; then
        local docker_config="${DOCKER_CONFIG:-$HOME/.docker}"
        mkdir -p "$docker_config/cli-plugins"
        if github_download "docker/compose" "docker-compose-linux-${SYS_ARCH}$" \
            "$docker_config/cli-plugins/docker-compose" \
            "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${SYS_ARCH}"; then
            chmod +x "$docker_config/cli-plugins/docker-compose"
            success "Docker Compose CLI plugin installed ($SYS_ARCH)"
        fi
    fi

    step_complete "Docker configured"
}

# ==============================================================================
# Step 13: KVM/QEMU Virtualization
# ==============================================================================
setup_kvm() {
    log "Setting up KVM/QEMU Virtualization..."

    if ! grep -E 'vmx|svm' /proc/cpuinfo &>/dev/null && [[ "$SYS_ARCH" == "x86_64" ]]; then
        warn "CPU virtualization extensions (VT-x/AMD-V) not detected in /proc/cpuinfo"
        if ! confirm "Continue installing KVM packages anyway?" "N"; then
            step_complete "KVM (skipped)"
            return 0
        fi
    fi

    run_sudo dnf install -y --skip-unavailable \
        qemu-kvm libvirt virt-install virt-manager libvirt-devel virt-top guestfs-tools gnome-boxes

    # Enable modern modular libvirt socket activation
    run_sudo systemctl disable --now libvirtd.service 2>/dev/null || true
    run_sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket 2>/dev/null || true

    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        run_sudo firewall-cmd --add-service=libvirt --permanent 2>/dev/null || true
        run_sudo firewall-cmd --reload 2>/dev/null || true
    fi

    if confirm "Install VirtIO paravirtualized drivers for Windows guest VMs?" "N"; then
        run_sudo wget -q https://fedorapeople.org/groups/virt/virtio-win/virtio-win.repo \
            -O /etc/yum.repos.d/virtio-win.repo 2>/dev/null || true
        run_sudo dnf install -y --skip-unavailable virtio-win || warn "VirtIO install failed"
    fi

    run_sudo usermod -aG libvirt,kvm "${USER:-$(id -un)}"

    # Ensure LIBVIRT_DEFAULT_URI is present across Bash, Zsh, and Fish
    if ! $DRY_RUN; then
        if [[ -f "$HOME/.bashrc" ]] && ! grep -q "LIBVIRT_DEFAULT_URI" "$HOME/.bashrc"; then
            backup_file "$HOME/.bashrc"
            echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> "$HOME/.bashrc"
        fi
        if [[ -f "$HOME/.zshrc" ]] && ! grep -q "LIBVIRT_DEFAULT_URI" "$HOME/.zshrc"; then
            backup_file "$HOME/.zshrc"
            echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> "$HOME/.zshrc"
        fi
        if [[ -f "$HOME/.config/fish/config.fish" ]] && ! grep -q "LIBVIRT_DEFAULT_URI" "$HOME/.config/fish/config.fish"; then
            backup_file "$HOME/.config/fish/config.fish"
            echo 'set -gx LIBVIRT_DEFAULT_URI "qemu:///system"' >> "$HOME/.config/fish/config.fish"
        fi
    fi

    step_complete "KVM/QEMU Virtualization configured"
}

# ==============================================================================
# Step 14: Gaming Stack (Steam, MangoHud, GameMode, Heroic)
# ==============================================================================
setup_gaming() {
    log "Installing Gaming Stack (Steam, MangoHud, GameMode, Heroic)..."

    run_sudo dnf install -y --skip-unavailable steam mangohud gamemode vulkan-tools

    if ! $DRY_RUN; then
        run_sudo dnf install -y --skip-unavailable steam-devices mozilla-openh264 2>/dev/null || true
    else
        dry "Unlock Steam H264 codec"
    fi

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
font_size=24
round_corners=8
EOF
        success "MangoHud configuration deployed"
    else
        dry "Create ~/.config/MangoHud/MangoHud.conf"
    fi

    if confirm "Install Heroic Games Launcher (Epic, GOG, Amazon Games) via Flathub?" "Y"; then
        if ! $DRY_RUN; then
            run flatpak install -y flathub com.heroicgameslauncher.hgl 2>/dev/null || warn "Heroic Flatpak install failed"
            mkdir -p "$HOME/Games/Heroic/Prefixes/shared" "$HOME/.var/app/com.heroicgameslauncher.hgl/config/MangoHud"
            if [[ -f "$HOME/.config/MangoHud/MangoHud.conf" ]]; then
                cp -p "$HOME/.config/MangoHud/MangoHud.conf" "$HOME/.var/app/com.heroicgameslauncher.hgl/config/MangoHud/MangoHud.conf" 2>/dev/null || true
            fi
        else
            dry "Install Heroic Games Launcher Flatpak and sync MangoHud config"
        fi
    fi

    step_complete "Gaming stack configured"
}

# ==============================================================================
# Step 15: Creator & Streaming Suite (OBS, v4l2loopback, Screen Recording)
# ==============================================================================
setup_creator() {
    log "Installing Creator & Streaming Suite..."

    local creator_pkgs=(
        obs-studio akmod-v4l2loopback v4l2loopback v4l-utils
        wf-recorder pulseaudio-utils gstreamer1-devel
    )
    run_sudo dnf install -y --skip-unavailable "${creator_pkgs[@]}"

    if $HAS_NVIDIA && confirm "Install NVIDIA Broadcast for Linux (AI noise removal & virtual camera)?" "N"; then
        if ! $DRY_RUN; then
            if [[ ! -d "$HOME/nvidia-broadcast-linux" ]]; then
                git clone --depth 1 --branch v1.5.2 https://github.com/Hkshoonya/nvidia-broadcast-linux.git "$HOME/nvidia-broadcast-linux" || warn "Failed to clone nvidia-broadcast-linux"
            fi
            if [[ -f "$HOME/nvidia-broadcast-linux/install.sh" ]]; then
                (cd "$HOME/nvidia-broadcast-linux" && ./install.sh --runtime cuda) || warn "NVIDIA Broadcast install finished with warnings"
            fi
        else
            dry "Clone and install NVIDIA Broadcast for Linux"
        fi
    fi

    step_complete "Creator suite configured"
}

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
    installed_kernel=$(rpm -q --last kernel-core 2>/dev/null | head -1 | awk '{print $1}' | sed 's/^kernel-core-//' || true)

    if [[ -n "$installed_kernel" && "$running_kernel" != "$installed_kernel" ]]; then
        warn "Kernel update detected:"
        info "  Running kernel:   $running_kernel"
        info "  Installed kernel: $installed_kernel"
        echo ""
        info "Rebooting before building GPU kernel modules ensures akmods targets the new kernel."
        info "Re-run this script after rebooting—it will resume automatically at the GPU Drivers step."
        if confirm "Reboot now?" "Y"; then
            mark_step_completed "setup_pre_driver_reboot"
            step_complete "Reboot checkpoint (rebooting)"
            run_sudo systemctl reboot
            exit 0
        else
            warn "Continuing without reboot; akmods will build for the target kernel."
        fi
    else
        info "Running kernel ($running_kernel) is up to date."
    fi

    step_complete "Kernel checkpoint verified"
}

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
            log "Hybrid Optimus laptop detected: Setting iGPU as primary Vulkan device to prevent dGPU wakeups..."
            local vulkan_conf="/etc/environment.d/10-vulkan-hybrid.conf"
            local selected_driver=""
            $HAS_AMD && selected_driver="*radeon*"
            [[ -z "$selected_driver" ]] && $HAS_INTEL && selected_driver="*intel*"

            if [[ -n "$selected_driver" ]] && ! $DRY_RUN; then
                run_sudo mkdir -p /etc/environment.d
                run_sudo tee "$vulkan_conf" > /dev/null <<EOF
# Prevent desktop apps from waking the discrete NVIDIA GPU unnecessarily
VK_LOADER_DRIVERS_SELECT=$selected_driver
EOF
                success "Hybrid Vulkan priority set to $selected_driver ($vulkan_conf)"
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
    info "Architecture: $SYS_ARCH | Chassis: $(if $IS_LAPTOP; then echo "Laptop"; else echo "Desktop"; fi)"
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

        if [[ $step_status -eq 0 ]]; then
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
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    trap 'echo -e "\n${RED}Interrupted by user${NC}"; cleanup; exit 1' INT TERM
    trap cleanup EXIT
    main "$@"
fi