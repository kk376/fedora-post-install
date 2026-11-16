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
        CHASSIS_TYPE="Laptop"
    elif systemd-detect-virt -q 2>/dev/null || [[ "$chassis" =~ ^(vm|container)$ ]]; then
        CHASSIS_TYPE="Virtual Machine / Container"
    elif [[ "$chassis" == "server" ]]; then
        CHASSIS_TYPE="Server"
    else
        CHASSIS_TYPE="Desktop"
    fi

    local gpu_info
    gpu_info=$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)
    if [[ -z "$gpu_info" ]] && [[ -d /sys/class/drm ]]; then
        gpu_info=$(cat /sys/class/drm/card*/device/uevent 2>/dev/null || true)
    fi
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
    if [[ ! -t 0 ]] && [[ -t 1 ]] && [[ -r /dev/tty ]]; then
        read -r -p "$prompt_text" reply < /dev/tty || reply=""
    else
        read -r -p "$prompt_text" reply || reply=""
    fi
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

    if [[ ! -t 0 ]] && [[ -t 1 ]] && [[ -r /dev/tty ]]; then
        read -p "$prompt $suffix: " -n 1 -r yn < /dev/tty || yn=""
    else
        read -p "$prompt $suffix: " -n 1 -r yn || yn=""
    fi
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
        # Prevent symlink attacks on output destination
        if [[ -L "$output" ]]; then
            rm -f "$output"
        fi
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
        chmod 0700 "$BACKUP_DIR" 2>/dev/null || true
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

            # Security: Reject path traversal attempts
            if [[ "$orig" == *".."* ]]; then
                warn "Security: Path traversal attempt detected in manifest ($orig) - skipped"
                continue
            fi

            # Security: Ensure absolute path
            if [[ "$orig" != /* ]]; then
                warn "Security: Non-absolute path detected in manifest ($orig) - skipped"
                continue
            fi

            # Security: Strict allowlist for privileged system configuration files (/etc)
            if [[ "$orig" == /etc/* ]]; then
                case "$orig" in
                    /etc/dnf/dnf.conf|/etc/systemd/zram-generator.conf) ;;
                    *)
                        warn "Security: Untrusted system configuration target ($orig) - skipped"
                        continue
                        ;;
                esac
            elif [[ "$orig" != "$HOME"/* && "$orig" != /tmp/* ]]; then
                warn "Security: Target outside allowed user directory ($orig) - skipped"
                continue
            fi

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

            # Security: Reject path traversal attempts or non-absolute paths
            if [[ "$orig" == *".."* || "$orig" != /* ]]; then
                continue
            fi

            # Security: Strict allowlist for privileged system configuration files (/etc)
            if [[ "$orig" == /etc/* ]]; then
                case "$orig" in
                    /etc/dnf/dnf.conf|/etc/systemd/zram-generator.conf) ;;
                    *)
                        warn "Security: Untrusted system configuration target ($orig) - skipped"
                        continue
                        ;;
                esac
            elif [[ "$orig" != "$HOME"/* && "$orig" != /tmp/* ]]; then
                warn "Security: Target outside allowed user directory ($orig) - skipped"
                continue
            fi

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

