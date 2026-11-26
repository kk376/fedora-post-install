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
                if $DRY_RUN; then
                    dry "Initialize rustup stable toolchain with clippy, rustfmt, rust-analyzer"
                elif [[ ! -f "$HOME/.cargo/bin/rustc" ]]; then
                    rustup-init -y --no-modify-path --default-toolchain stable
                    "$HOME/.cargo/bin/rustup" component add clippy rustfmt rust-analyzer
                    success "Rust toolchain initialized via rustup"
                else
                    info "Rustup toolchain already initialized"
                fi
                ;;
            2)
                run_sudo dnf install -y rust cargo clippy rustfmt rust-analyzer
                ;;
            *) info "Skipping Rust installation" ;;
        esac

        if confirm "Install and configure ccache (10GB compressed compiler cache)?" "Y"; then
            run_sudo dnf install -y --skip-unavailable ccache
            if ! $DRY_RUN; then
                mkdir -p "$HOME/.ccache"
                ccache --set-config=cache_dir="$HOME/.ccache" 2>/dev/null || true
                ccache --set-config=max_size=10G 2>/dev/null || true
                ccache --set-config=compression=true 2>/dev/null || true
                success "ccache configured (10GB limit)"
            else
                dry "Configure ccache: 10GB max size, compression enabled"
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

        if confirm "Install Scrcpy (Android screen mirroring via COPR)?" "Y"; then
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

        if [[ "${IS_CONTAINER:-false}" != "true" ]]; then
            if $HAS_NVIDIA; then
                if confirm "NVIDIA GPU detected: Install CUDA development toolkit?" "N"; then
                    run_sudo dnf install -y --skip-unavailable xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-cuda-devel
                fi
            fi

            # Offer ROCm only if AMD is a discrete/workstation GPU (avoids unsupported installs on APUs)
            if $HAS_AMD && { lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -i amd | grep -Eiq 'Navi|Radeon RX|Radeon PRO|Instinct|RDNA|Discrete'; }; then
                if confirm "AMD Radeon discrete GPU detected: Install ROCm HIP & OpenCL compute runtime?" "N"; then
                    run_sudo dnf install -y --skip-unavailable rocm-hip rocm-opencl rocm-clinfo rocm-smi
                fi
            fi

            if $HAS_INTEL && [[ "${SYS_ARCH:-$(uname -m)}" == "x86_64" ]] && [[ "${INTEL_VAAPI_PKG:-intel-media-driver}" != "libva-intel-driver" ]]; then
                if confirm "Intel GPU detected: Install Intel Compute Runtime (Level Zero / OpenCL)?" "N"; then
                    run_sudo dnf install -y --skip-unavailable intel-compute-runtime oneapi-level-zero
                fi
            fi
        fi
    fi

    # Configure Python symlink & optional Git sensible defaults
    if ! $DRY_RUN; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v python3 || echo /usr/bin/python3)" "$HOME/.local/bin/python" 2>/dev/null || true
    fi

    if confirm "Configure sensible Git workflow defaults (autoSetupRemote, pull.rebase, diff.colorMoved)?" "N"; then
        if ! $DRY_RUN; then
            backup_file "$HOME/.gitconfig"
            git config --global push.autoSetupRemote true 2>/dev/null || true
            git config --global pull.rebase true 2>/dev/null || true
            git config --global diff.colorMoved zebra 2>/dev/null || true
            success "Git workflow defaults applied"
        else
            dry "Configure git push.autoSetupRemote, pull.rebase, and diff.colorMoved"
        fi
    fi

    # PostgreSQL Server
    if confirm "Install and initialize PostgreSQL Server?" "N"; then
        if ! $DRY_RUN; then
            log "Installing PostgreSQL from official Fedora repositories..."
            if run_sudo dnf install -y postgresql-server postgresql; then
                run_sudo postgresql-setup --initdb 2>/dev/null || true
                run_sudo systemctl enable --now postgresql
                success "PostgreSQL initialized and running"
            fi
        else
            dry "Install and initialize PostgreSQL Server"
        fi
    fi

    step_complete "Development toolchains configured"
}

