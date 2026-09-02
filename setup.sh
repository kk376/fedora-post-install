#!/bin/bash
# Fedora 44 Post-Install Setup Script
# Author: Kushagra Kumar
# Version: 5.4.0

set -euo pipefail

# ==============================================================================
# Configuration & Flags
# ==============================================================================
DRY_RUN=false
BACKUP_DIR="$HOME/.config/fedora-setup-backups/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/fedora-setup-$(date +%Y%m%d_%H%M%S).log"
SCRIPT_VERSION="5.4.0"
PROFILE="full"
FORCE_RERUN=false
# State checkpoint tracking enables idempotent step skipping and seamless resumption across driver reboots.
STATE_FILE="$HOME/.config/fedora-setup/state.txt"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --profile=*)
            PROFILE="${1#*=}"
            shift
            ;;
        --profile)
            if [[ $# -lt 2 ]]; then
                echo "Error: Option --profile requires an argument." >&2
                exit 1
            fi
            PROFILE="$2"
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
            echo "  --profile=PROFILE      Choose setup profile:"
            echo "                           minimal     - DNF, DNS, fonts, shell, browser/codecs"
            echo "                           dev         - Complete dev stack, Docker, Antigravity, KVM"
            echo "                           gaming      - Multimedia, Steam, MangoHud, Flatpaks, GPU drivers"
            echo "                           workstation - Productive desktop, Steam, KVM, GPU drivers"
            echo "                           creator     - Gaming, Creator tools, KVM, GPU drivers"
            echo "                           full        - All steps including COPR & Debian packaging (default)"
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

# Validate profile
case "$PROFILE" in
    minimal|dev|gaming|workstation|creator|full) ;;
    *) echo "Unknown profile: $PROFILE (use minimal, dev, gaming, workstation, creator, or full)"; exit 1 ;;
esac

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Enable logging to file
exec > >(tee -a "$LOG_FILE") 2>&1

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
    [[ "$PROFILE" == "gaming" || "$PROFILE" == "workstation" || "$PROFILE" == "creator" || "$PROFILE" == "full" ]]
}

is_creator_profile() {
    [[ "$PROFILE" == "creator" || "$PROFILE" == "workstation" || "$PROFILE" == "full" ]]
}

is_dev_profile() {
    [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]
}

verify_checksum() {
    local file="$1" expected="$2"
    local actual
    actual=$(sha256sum "$file" | cut -d' ' -f1)
    if [[ "$actual" != "$expected" ]]; then
        log_error "Checksum mismatch for $file"
        log_error "  Expected: $expected"
        log_error "  Actual:   $actual"
        return 1
    fi
    log_info "Checksum verified: $file"
}

# Download a release asset from GitHub with progressive JSON parser fallback (jq -> python3 -> regex).
# Usage: github_download <owner/repo> <asset_pattern> <output_path> [fallback_url]
# asset_pattern is a grep -E regex to match the asset filename.
github_download() {
    local repo="$1" pattern="$2" output="$3" fallback="${4:-}"
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
        curl -fL --max-time 120 -o "$output" "$download_url" 2>/dev/null
        return $?
    fi
    return 1
}

# Backup a file before modifying
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if $DRY_RUN; then
            dry "Backup: $file → $BACKUP_DIR/$(basename "$file").backup"
            return 0
        fi
        mkdir -p "$BACKUP_DIR"
        local backup_name=$(basename "$file").backup
        cp "$file" "$BACKUP_DIR/$backup_name"
        info "Backed up: $file → $BACKUP_DIR/$backup_name"
    fi
}

# Restore system and user configuration files from the most recent backup timestamp.
# Purges STATE_FILE upon restoration to force full step re-evaluation on subsequent runs.
restore_backups() {
    local latest_backup
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

    local originals=(
        "$HOME/.zshrc"
        "$HOME/.bashrc"
        "/etc/dnf/dnf.conf"
        "$HOME/.config/MangoHud/MangoHud.conf"
        "$HOME/.config/starship.toml"
        "$HOME/.config/kitty/kitty.conf"
    )

    for orig in "${originals[@]}"; do
        local name backup_path
        name="$(basename "$orig")"
        backup_path="$latest_backup/$name.backup"

        if [[ ! -f "$backup_path" ]]; then
            warn "No backup for $orig"
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
    local packages=("zsh" "brave-browser" "vesktop" "zed" "codium" "agy" "code" "docker" "tlp" "steam" "ffmpeg")
    for pkg in "${packages[@]}"; do
        if rpm -q "$pkg" &>/dev/null; then
            echo "  ✅ $pkg: $(rpm -q --queryformat '%{VERSION}' "$pkg" 2>/dev/null)"
        elif command -v "$pkg" &>/dev/null; then
            echo "  ✅ $pkg: $("$pkg" --version 2>/dev/null | head -1 || echo "installed")"
        else
            echo "  ❌ $pkg: not installed"
        fi
    done
}

# Refresh sudo timestamp in background subshell loop to prevent auth expiry during long DNF or compilation tasks.
# Loop terminates automatically when parent script process ($$) exits.
SUDO_PID=""
if ! $DRY_RUN; then
    sudo -v || { error "Requires sudo"; exit 1; }
    while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
    SUDO_PID=$!
fi

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
# ZSH + Starship
# ==============================================================================
setup_shell() {
    log "Installing ZSH & Starship..."
    run_sudo dnf install -y --skip-unavailable zsh curl git fontconfig

    if ! command -v starship &>/dev/null && ! $DRY_RUN; then
        if ! run_sudo dnf install -y --skip-unavailable starship 2>/dev/null; then
            log "Installing Starship via official installer..."
            curl -sS https://starship.rs/install.sh | sh -s -- -y >/dev/null 2>&1 || true
        fi
    fi

    if ! $DRY_RUN; then
        mkdir -p "$HOME/.zsh/plugins" "$HOME/.config"

        [[ ! -d "$HOME/.zsh/plugins/zsh-autosuggestions" ]] && run git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/plugins/zsh-autosuggestions" 2>/dev/null || true
        [[ ! -d "$HOME/.zsh/plugins/zsh-syntax-highlighting" ]] && run git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.zsh/plugins/zsh-syntax-highlighting" 2>/dev/null || true

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

        backup_file "$HOME/.zshrc"

        if is_dev_profile; then
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
export PAGER=cat
export SYSTEMD_PAGER=cat
export MANPAGER=cat
export BAT_PAGER=""
export DELTA_PAGER=cat
export LESS="-F -X -R"
export PATH="$HOME/.local/bin:$PATH"

# ===== NVM =====
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# ===== Starship (ALWAYS LAST) =====
eval "$(starship init zsh)"
ZSHRC_DEV
        else
            log "Configuring standard .zshrc..."
            cat > "$HOME/.zshrc" <<'ZSHRC_NORMAL'
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
alias ls='eza --group-directories-first --classify --icons --git'
alias cat='bat --paging=never --style=plain'

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
export PAGER=cat
export SYSTEMD_PAGER=cat
export MANPAGER=cat
export BAT_PAGER=""
export DELTA_PAGER=cat
export LESS="-F -X -R"
export PATH="$HOME/.local/bin:$PATH"

# ===== Starship (ALWAYS LAST) =====
eval "$(starship init zsh)"
ZSHRC_NORMAL
        fi

        # Also ensure ~/.bashrc has Starship and aliases for non-Zsh sessions
        if ! grep -q "starship init bash" "$HOME/.bashrc" 2>/dev/null; then
            cat >> "$HOME/.bashrc" << 'BASHRC_STARSHIP'

# ===== Starship, Aliases & Pager Suppression =====
export PAGER=cat
export SYSTEMD_PAGER=cat
export MANPAGER=cat
export BAT_PAGER=""
export DELTA_PAGER=cat
export LESS="-F -X -R"
alias ls='eza --group-directories-first --classify --icons --git'
alias cat='bat --paging=never --style=plain'
eval "$(starship init bash)"
BASHRC_STARSHIP
        fi
    else
        dry "Install Starship, clone plugins, deploy starship.toml, .zshrc, and .bashrc"
    fi

    # Configure Kitty terminal emulator (interactive option)
    if confirm "Install and configure Kitty terminal emulator?" "Y"; then
        log "Installing Kitty terminal..."
        run_sudo dnf install -y --skip-unavailable kitty

        if ! $DRY_RUN; then
            log "Deploying Kitty terminal configuration..."
            mkdir -p "$HOME/.config/kitty"
            backup_file "$HOME/.config/kitty/kitty.conf"
            cat > "$HOME/.config/kitty/kitty.conf" <<'KITTY_CONF'
# --- Typography & Font Ligatures ---
font_family      Fira Code
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        12
disable_ligatures never

# --- Translucency & Styling ---
background_opacity         0.97
background_blur            95
dynamic_background_opacity yes
window_padding_width       14 16
hide_window_decorations    no
wayland_titlebar_color     background
linux_display_server       wayland
confirm_os_window_close    0

# --- Cursor Customization ---
cursor_shape          beam
cursor_beam_thickness 1.8
cursor_blink_interval 0.5

# Right-click pastes from clipboard
mouse_map right press ungrabbed paste_from_clipboard

# --- Tab Bar (Hidden on single tab, seamless dark integration when 2+ tabs) ---
tab_bar_edge        bottom
tab_bar_style       powerline
tab_powerline_style slanted
tab_bar_min_tabs    2
tab_bar_background  #1a1b26
tab_title_template  " {index}: {title} "

active_tab_font_style   bold
inactive_tab_font_style normal

# --- Tab & Window Keybindings ---
map ctrl+shift+t new_tab
map ctrl+t new_tab
map ctrl+shift+w close_tab
map ctrl+w close_tab
map ctrl+tab next_tab
map ctrl+shift+tab previous_tab
map ctrl+shift+right next_tab
map ctrl+shift+left previous_tab
map alt+1 goto_tab 1
map alt+2 goto_tab 2
map alt+3 goto_tab 3
map alt+4 goto_tab 4
map alt+5 goto_tab 5
map ctrl+shift+enter new_window
map ctrl+shift+[ previous_window
map ctrl+shift+] next_window
map ctrl+shift+k combine : clear_terminal scrollback active : send_text normal,application \x0c
map ctrl+l combine : clear_terminal scroll active : send_text normal,application \x0c

# --- Audio & Shell ---
enable_audio_bell no
shell zsh

# --- Tokyo Night Color Scheme ---
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
            success "Kitty terminal installed and configured"
        else
            dry "Deploy Kitty terminal configuration to ~/.config/kitty/kitty.conf"
        fi
    else
        info "Skipping Kitty terminal installation and configuration"
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

    confirm "Set ZSH as default shell?" "Y" && run chsh -s "$(command -v zsh)"

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
    run_sudo dnf group upgrade -y multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
    run_sudo dnf group upgrade -y sound-and-video

    # WirePlumber Bluetooth High-Definition Audio (prioritize AAC, SBC-XQ, LDAC)
    log "Configuring WirePlumber Bluetooth audio optimization..."
    if ! $DRY_RUN; then
        mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
        cat > "$HOME/.config/wireplumber/wireplumber.conf.d/50-bluez.conf" <<'BLUEZ_CONF'
monitor.bluez.properties = {
  bluez5.roles = [ a2dp_sink a2dp_source bap_sink bap_source hfp_hf hfp_ag hsp_hs hsp_ag ]
  bluez5.codecs = [ ldac aac aptx_hd aptx sbc_xq sbc ]
  bluez5.enable-sbc-xq = true
  bluez5.enable-msbc = true
  bluez5.enable-hw-volume = true
}
BLUEZ_CONF
        systemctl --user restart wireplumber 2>/dev/null || true
        success "WirePlumber Bluetooth HD audio configured"
    else
        dry "Deploy WirePlumber 50-bluez.conf and restart wireplumber service"
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

    # Swap standard Mesa drivers with RPM Fusion freeworld builds to unlock patent-encumbered H.264/H.265/VC-1 VA-API codecs
    if [[ -n "$GPU_AMD" ]]; then
        log "AMD GPU Detected: Swapping for freeworld drivers..."
        run_sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
        run_sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
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

        if [[ "$CHASSIS" == "laptop" || "$CHASSIS" == "notebook" || "$CHASSIS" == "convertible" ]]; then
            log "Laptop detected. Checking for Optimus/Hybrid setup..."
            if [[ -n "$GPU_INTEL" || -n "$GPU_AMD" ]]; then
                log "Hybrid Graphics (Optimus) detected."
            else
                log "Dedicated Nvidia only (MUX Switch or Desktop replacement)."
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
        google-noto-sans-fonts google-noto-serif-fonts google-noto-mono-fonts google-carlito-fonts google-caladea-fonts \
        curl cabextract xorg-x11-font-utils fontconfig

    run curl -sLO https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
    run_sudo rpm -ivh --nodigest --nofiledigest msttcore-fonts-installer-2.6-1.noarch.rpm 2>/dev/null || true
    run rm -f msttcore-fonts-installer-2.6-1.noarch.rpm

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

    step_complete "Fonts installed"
}

# ==============================================================================
# GNOME Tools
# ==============================================================================
setup_gnome() {
    log "Installing GNOME tools and extensions..."
    run_sudo dnf install -y gnome-tweaks gnome-shell-extension-gsconnect

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

    step_complete "GNOME tools and GSConnect configured"
}

# ==============================================================================
# Essential Packages
# ==============================================================================
setup_packages() {
    log "Installing essential packages..."

    local pkgs_to_install=(
        gcc clang fastfetch make cmake perl wmctrl cargo maven bat eza \
        fd-find ripgrep fzf zoxide ruff python-unversioned-command \
        java-latest-openjdk java-latest-openjdk-devel nodejs python3 python3-pip wget htop duf sassc unzip unrar \
        p7zip p7zip-plugins ntfs-3g gparted timeshift vlc qbittorrent wl-clipboard \
        telegram-desktop vim neovim gh libva-utils gstreamer1-plugin-openh264 android-tools
    )

    if is_gaming_profile; then
        pkgs_to_install+=(steam mangohud)
    fi

    if is_creator_profile; then
        pkgs_to_install+=(obs-studio v4l-utils gtk4-devel libadwaita-devel gstreamer1-devel libayatana-appindicator-gtk3 pulseaudio-utils)
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
background_alpha=0.3
font_size=20
EOF
                success "MangoHud config created"
            else
                dry "Create ~/.config/MangoHud/MangoHud.conf"
            fi
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
                        git clone --depth 1 https://github.com/Hkshoonya/nvidia-broadcast-linux.git "$HOME/nvidia-broadcast-linux" || true
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

    step_complete "Essential packages installed"
}

# ==============================================================================
# Development Tools & Compilers
# ==============================================================================
setup_dev() {
    log "Installing dev tools & libraries..."

    local dev_pkgs=(
        meson ninja-build automake autoconf libtool pkg-config bear
        gdb valgrind strace ltrace clang-tools-extra
        bc bison flex protobuf-compiler python3-protobuf libxml2 libxslt
        ImageMagick git-lfs git-filter-repo gnupg lz4 rsync zip
        python3-devel python3-virtualenv python3-wheel python3-setuptools
        openssl-devel zlib-devel elfutils-libelf-devel elfutils-devel gnutls-devel
    )

    if [[ "$PROFILE" == "full" ]]; then
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

    if confirm "Install full Rust toolchain (rustup, clippy, rust-analyzer)?" "Y"; then
        run_sudo dnf install -y rust cargo rustup rustfmt clippy rust-analyzer 2>/dev/null || true
    fi

    if command -v ccache &>/dev/null || $DRY_RUN; then
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

    if command -v npm &>/dev/null; then
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
                    if curl -fsSL https://zed.dev/install.sh | bash 2>/dev/null; then
                        success "Zed installed via official installer script"
                    else
                        warn "Zed installation failed - install manually from https://zed.dev"
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
                    curl -fsSL https://antigravity.google/cli/install.sh | bash 2>/dev/null || \
                        warn "Antigravity install failed - try manually: curl -fsSL https://antigravity.google/cli/install.sh | bash"
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
    run flatpak install -y flathub org.localsend.localsend_app io.missioncenter.MissionCenter com.vysp3r.ProtonPlus 2>/dev/null || true

    info "ProtonPlus installed - Use for Proton GE:"
    info "  • Only use if a game has issues with default Proton"
    info "  • Install latest Proton GE version from ProtonPlus"
    info "  • Set per-game in Steam: Properties → Compatibility"

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
    info "  • Paravirtualized storage (virtio-blk/scsi) and network (virtio-net) drivers for Windows guest VMs under KVM/QEMU."
    info "  • Recommendation: Install if you plan to run Windows virtual machines with high performance disk/network I/O. Otherwise skip."
    if confirm "Install VirtIO drivers (required for Windows VMs)?" "Y"; then
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
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local mins=$((duration / 60)) secs=$((duration % 60))

    echo -e "\n${GREEN}=== INSTALLATION SUMMARY ===${NC}"
    echo "Time: ${mins}m ${secs}s | Steps: ${COMPLETED_STEPS} completed, ${FAILED_STEPS} failed, ${SKIPPED_STEPS} skipped (of ${TOTAL_STEPS})"

    echo "Service Status:"
    systemctl is-active --quiet tlp && echo "  ✅ TLP" || echo "  ❌ TLP"
    systemctl is-active --quiet docker && echo "  ✅ Docker" || echo "  ❌ Docker"
    command -v nvidia-smi &>/dev/null && echo "  ✅ NVIDIA drivers"
    [[ "${SHELL:-}" == "$(command -v zsh 2>/dev/null)" ]] && echo "  ✅ ZSH default" || echo "  ⚠️  ZSH: not default shell"

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
    echo "2. Open a new terminal to start using ZSH + Starship"
    echo "3. Review the log file: $LOG_FILE"
    echo -e "${GREEN}System ready! 🚀${NC}"
}

# ==============================================================================
# Main
# ==============================================================================
main() {
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
    PROFILE_STEPS[dev]="setup_dnf setup_dns setup_power setup_nosleep setup_fonts setup_shell setup_browser_multimedia setup_gnome setup_packages setup_dev setup_editor setup_docker setup_kvm setup_pre_driver_reboot setup_drivers"
    PROFILE_STEPS[gaming]="setup_dnf setup_dns setup_power setup_fonts setup_shell setup_browser_multimedia setup_gnome setup_packages setup_flatpaks setup_pre_driver_reboot setup_drivers"
    PROFILE_STEPS[workstation]="setup_dnf setup_dns setup_power setup_fonts setup_shell setup_browser_multimedia setup_gnome setup_packages setup_flatpaks setup_kvm setup_pre_driver_reboot setup_drivers"
    PROFILE_STEPS[creator]="setup_dnf setup_dns setup_power setup_fonts setup_shell setup_browser_multimedia setup_gnome setup_packages setup_flatpaks setup_kvm setup_pre_driver_reboot setup_drivers"
    PROFILE_STEPS[full]=""

    info "Profile: $PROFILE"
    [[ -n "${PROFILE_STEPS[$PROFILE]}" ]] && info "Running steps: ${PROFILE_STEPS[$PROFILE]}"

    init_state

    # Filter execution sequence based on active profile and check completion state for idempotency
    local filtered_steps=()
    for step in "${steps[@]}"; do
        IFS=':' read -r func _ <<< "$step"
        if [[ -z "${PROFILE_STEPS[$PROFILE]}" ]] || [[ " ${PROFILE_STEPS[$PROFILE]} " =~ " $func " ]]; then
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
            if $func; then
                if ! $DRY_RUN; then
                    mark_step_completed "$func"
                fi
            else
                warn "$name had issues"
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
    [[ -n "$SUDO_PID" ]] && kill "$SUDO_PID" 2>/dev/null || true
}
trap 'echo -e "\n${RED}Interrupted${NC}"; cleanup; exit 1' INT TERM
trap cleanup EXIT
main "$@"