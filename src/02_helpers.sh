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

# Return 0 only if a system chassis battery exists (ignores UPS/peripheral Device batteries).
is_system_battery_present() {
    local ps_root="${1:-/sys/class/power_supply}"
    local bat scope
    for bat in "$ps_root"/BAT*; do
        [[ -d "$bat" ]] || continue
        scope=$(cat "$bat/scope" 2>/dev/null || echo "System")
        [[ "$scope" != "Device" ]] && return 0
    done
    return 1
}

# Select libva-intel-driver (i965) for legacy Gen4-Gen7.5 Intel GPUs, else intel-media-driver (iHD).
intel_vaapi_driver_for_pci() {
    local pci_text="${1:-}"
    if grep -Eiq '8086:(004[0-9a-f]|010[0-9a-f]|011[0-9a-f]|012[0-9a-f]|015[0-9a-f]|016[0-9a-f]|040[0-9a-f]|041[0-9a-f]|042[0-9a-f]|0a0[0-9a-f]|0a1[0-9a-f]|0a2[0-9a-f]|0d1[0-9a-f]|0d2[0-9a-f]|0f3[0-9a-f]|2a4[0-9a-f])' <<< "$pci_text"; then
        echo "libva-intel-driver"
    else
        echo "intel-media-driver"
    fi
}

# Detect hardware once at startup so all functions can make hardware-aware decisions
detect_hardware() {
    local chassis dmi_chassis
    chassis=$(hostnamectl chassis 2>/dev/null || echo "unknown")
    dmi_chassis=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "")

    if systemd-detect-virt --container -q 2>/dev/null || [[ "$chassis" == "container" ]]; then
        IS_CONTAINER=true
        CHASSIS_TYPE="Container"
    elif systemd-detect-virt -q 2>/dev/null || [[ "$chassis" == "vm" ]]; then
        IS_VM=true
        CHASSIS_TYPE="Virtual Machine"
    elif [[ "$chassis" =~ ^(laptop|notebook|convertible|portable)$ ]] || \
         [[ "$dmi_chassis" =~ ^(8|9|10|11|14|30|31|32)$ ]] || \
         is_system_battery_present "/sys/class/power_supply"; then
        IS_LAPTOP=true
        CHASSIS_TYPE="Laptop"
    elif [[ "$chassis" == "server" ]]; then
        CHASSIS_TYPE="Server"
    else
        CHASSIS_TYPE="Desktop"
    fi

    compgen -G "/sys/class/bluetooth/hci*" > /dev/null && HAS_BLUETOOTH=true

    local root_fstype
    root_fstype=$(findmnt -n -o FSTYPE / 2>/dev/null || stat -f -c %T / 2>/dev/null || echo "")
    [[ "$root_fstype" == "btrfs" ]] && HAS_BTRFS=true

    local gpu_info
    gpu_info=$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)
    if [[ -z "$gpu_info" ]] && [[ -d /sys/class/drm ]]; then
        gpu_info=$(cat /sys/class/drm/card*/device/uevent 2>/dev/null || true)
    fi
    if grep -Eiq 'nvidia|10de:|DRIVER=nouveau|DRIVER=nvidia' <<< "$gpu_info"; then HAS_NVIDIA=true; fi
    if grep -Eiq 'amd|advanced micro devices|ati|1002:|DRIVER=amdgpu|DRIVER=radeon' <<< "$gpu_info"; then HAS_AMD=true; fi
    if grep -Eiq 'intel|8086:|DRIVER=i915|DRIVER=xe' <<< "$gpu_info"; then
        HAS_INTEL=true
        local intel_ids
        intel_ids=$(lspci -n 2>/dev/null | grep -Eo '8086:[0-9a-fA-F]{4}' || cat /sys/class/drm/card*/device/uevent 2>/dev/null || true)
        INTEL_VAAPI_PKG=$(intel_vaapi_driver_for_pci "$intel_ids")
    fi
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

init_run_tmp_dir() {
    if [[ -z "${RUN_TMP_DIR:-}" || ! -d "${RUN_TMP_DIR:-}" ]]; then
        RUN_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fedora-setup-run.XXXXXX")
        chmod 0700 "$RUN_TMP_DIR"
    fi
}

cleanup_run_tmp() {
    if [[ -n "${RUN_TMP_DIR:-}" && -d "$RUN_TMP_DIR" ]]; then
        rm -rf "$RUN_TMP_DIR"
        RUN_TMP_DIR=""
    fi
}

# Download a release asset from GitHub with progressive JSON parser fallback (jq -> python3 -> regex).
github_download() {
    local repo="$1" pattern="$2" output="$3" fallback="${4:-}" expected_sha256="${5:-}"
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local download_url="" asset_digest="" api_response

    api_response=$(curl --proto '=https' --tlsv1.2 -sfL --max-time 10 "$api_url" 2>/dev/null || true)
    if [[ -n "$api_response" ]]; then
        if command -v jq &>/dev/null; then
            local jq_line
            jq_line=$(echo "$api_response" | jq -r --arg pat "$pattern" '[.assets[] | select(.name | test($pat)) | (.browser_download_url + "\t" + (.digest // ""))] | first // empty' 2>/dev/null || true)
            download_url="${jq_line%%$'\t'*}"
            [[ "$jq_line" == *$'\t'* ]] && asset_digest="${jq_line#*$'\t'}"
        elif command -v python3 &>/dev/null; then
            local py_line
            py_line=$(python3 -c "
import sys, json, re
try:
    data = json.loads(sys.stdin.read())
    pat = re.compile(sys.argv[1])
    for a in data.get('assets', []):
        if pat.search(a.get('name', '')):
            print(f\"{a.get('browser_download_url', '')}\t{a.get('digest') or ''}\")
            break
except Exception:
    pass
" "$pattern" <<< "$api_response" 2>/dev/null || true)
            download_url="${py_line%%$'\t'*}"
            [[ "$py_line" == *$'\t'* ]] && asset_digest="${py_line#*$'\t'}"
        else
            download_url=$(echo "$api_response" | grep -oP '"browser_download_url":\s*"\K[^"]*' 2>/dev/null | grep -E "$pattern" 2>/dev/null | head -1 || true)
        fi
    fi

    if [[ -z "$download_url" ]]; then
        download_url="$fallback"
        asset_digest=""
    fi

    if [[ -z "$expected_sha256" && "$asset_digest" =~ ^sha256:([0-9a-fA-F]{64})$ ]]; then
        expected_sha256="${BASH_REMATCH[1]}"
    fi

    if [[ -n "$download_url" ]]; then
        # Prevent symlink attacks on output destination
        if [[ -L "$output" ]]; then
            rm -f "$output"
        fi
        if curl --proto '=https' --tlsv1.2 -fL --max-time 120 -o "$output" "$download_url" 2>/dev/null; then
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

# Backup a file before modifying (preserves directory hierarchy and original snapshot)
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
        if [[ -e "$backup_path" ]]; then
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

_is_valid_restore_target() {
    local orig="$1"
    if [[ "$orig" == *".."* ]]; then
        warn "Security: Path traversal attempt detected in manifest ($orig) - skipped"
        return 1
    fi
    if [[ "$orig" != /* ]]; then
        warn "Security: Non-absolute path detected in manifest ($orig) - skipped"
        return 1
    fi
    if [[ "$orig" == /etc/* ]]; then
        case "$orig" in
            /etc/dnf/dnf.conf|/etc/systemd/zram-generator.conf) return 0 ;;
            *)
                warn "Security: Untrusted system configuration target ($orig) - skipped"
                return 1
                ;;
        esac
    fi
    if [[ "$orig" != "$HOME"/* ]]; then
        warn "Security: Target outside allowed user directory ($orig) - skipped"
        return 1
    fi
    return 0
}

_restore_single_file() {
    local src="$1" orig="$2"
    if $DRY_RUN; then
        dry "cp -p $src $orig"
    elif [[ "$orig" == /etc/* ]]; then
        run_sudo cp -p "$src" "$orig"
        success "Restored: $orig"
    else
        mkdir -p "$(dirname "$orig")"
        cp -p "$src" "$orig"
        success "Restored: $orig"
    fi
}

_find_latest_backup_dir() {
    local backup_root="$1"
    local candidate latest=""
    [[ -d "$backup_root" ]] || return 1
    for candidate in "$backup_root"/*/; do
        [[ -d "$candidate" ]] || continue
        candidate="${candidate%/}"
        if [[ -z "$latest" ]] || [[ "$candidate" -nt "$latest" ]] || { [[ ! "$latest" -nt "$candidate" ]] && [[ "$(basename "$candidate")" > "$(basename "$latest")" ]]; }; then
            latest="$candidate"
        fi
    done
    [[ -n "$latest" ]] && printf '%s\n' "$latest"
}

restore_backups() {
    local latest_backup
    latest_backup=$(_find_latest_backup_dir "$HOME/.config/fedora-setup-backups" || true)
    if [[ -z "$latest_backup" ]]; then
        warn "No backups found"
        return 1
    fi

    log "Latest backup: $latest_backup"
    if ! confirm "Restore all files from this backup?" "N"; then
        return 0
    fi

    if [[ -f "$latest_backup/.manifest" ]]; then
        while IFS= read -r orig; do
            [[ -z "$orig" ]] && continue
            _is_valid_restore_target "$orig" || continue

            local backup_path="$latest_backup/${orig#/}"
            if [[ ! -f "$backup_path" ]]; then
                warn "No backup for $orig at $backup_path"
                continue
            fi
            _restore_single_file "$backup_path" "$orig"
        done < "$latest_backup/.manifest"
    elif compgen -G "$latest_backup/*/*" >/dev/null; then
        while IFS= read -r -d '' bfile; do
            [[ "$(basename "$bfile")" == ".manifest" ]] && continue
            local rel_path="${bfile#"$latest_backup"/}"
            local orig="/$rel_path"
            _is_valid_restore_target "$orig" || continue
            _restore_single_file "$bfile" "$orig"
        done < <(find "$latest_backup" -mindepth 2 -type f -print0)
    else
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
            local backup_path
            backup_path="$latest_backup/$(basename "$orig").backup"
            [[ -f "$backup_path" ]] || continue
            _restore_single_file "$backup_path" "$orig"
        done
    fi

    if ! $DRY_RUN; then
        rm -f "$STATE_FILE"
        warn "State reset due to restore - all steps will re-run on next execution"
    fi
}

