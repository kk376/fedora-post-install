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
                        init_run_tmp_dir
                        local zed_installer
                        zed_installer=$(mktemp "$RUN_TMP_DIR/zed-install.XXXXXX.sh")
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

RUN_TMP=$(mktemp -d "${TMPDIR:-/tmp}/zed-run.XXXXXX")
cleanup_zed_run() { rm -rf "$RUN_TMP"; }
drop_to_shell() {
    cleanup_zed_run
    echo -e "\n\033[1;33m[Interrupted. Interactive shell active:]\033[0m"
    exec "$LOGIN_SH"
}
trap drop_to_shell INT TERM
trap cleanup_zed_run EXIT

echo -e "\033[1;34m==>\033[0m \033[1;32mRunning:\033[0m $NAME"
cd "$DIR" || exit 1

case "$EXT" in
    py)  python3 "$FILE" ;;
    rs)
        if [[ -f "Cargo.toml" || -f "../Cargo.toml" ]]; then
            cargo run
        else
            rustc "$FILE" -o "$RUN_TMP/$BASE" && "$RUN_TMP/$BASE"
        fi
        ;;
    c)   gcc -O2 "$FILE" -o "$RUN_TMP/$BASE" -lm && "$RUN_TMP/$BASE" ;;
    cpp|cc|cxx) g++ -O2 "$FILE" -o "$RUN_TMP/$BASE" && "$RUN_TMP/$BASE" ;;
    go)  go run "$FILE" ;;
    js)  node "$FILE" ;;
    ts)  npx tsx "$FILE" 2>/dev/null || npx ts-node "$FILE" ;;
    sh|bash) bash "$FILE" ;;
    *)   echo "[Zed Runner] Unsupported file extension: .$EXT" ;;
esac

cleanup_zed_run
trap - EXIT INT TERM

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
                    init_run_tmp_dir
                    local agy_installer
                    agy_installer=$(mktemp "$RUN_TMP_DIR/agy-install.XXXXXX.sh")
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

