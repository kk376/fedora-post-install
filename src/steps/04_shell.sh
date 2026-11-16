# ==============================================================================
# Step 4: Shell Environment, Starship & Terminal Emulator
# ==============================================================================
deploy_terminal_config() {
    local target="$1"

    case "$target" in
        ghostty)
            log "Deploying Ghostty tab configuration..."
            if ! $DRY_RUN; then
                mkdir -p "$HOME/.config/ghostty"
                backup_file "$HOME/.config/ghostty/config.ghostty"
                cat > "$HOME/.config/ghostty/config.ghostty" <<'GHOSTTY_CONF'
theme = tokyonight
gtk-tabs-location = bottom
gtk-wide-tabs = false
gtk-toolbar-style = flat
window-new-tab-position = end
tab-inherit-working-directory = false
GHOSTTY_CONF
                success "Ghostty configuration deployed to ~/.config/ghostty/config.ghostty"
            else
                dry "Deploy Ghostty configuration to ~/.config/ghostty/config.ghostty"
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

