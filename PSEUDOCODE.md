# Fedora 44 Post-Install: Complete Logic Specification & Layman Pseudocode

Welcome to the comprehensive logic breakdown of the **Fedora 44 Post-Install Setup Script (`setup.sh`)**.

This document is written for humans—whether you are a beginner looking to understand exactly what this script touches on your machine before running it, or a developer wanting a clean, structured pseudocode reference of the entire architecture.

---

## Table of Contents

1. [High-Level Architecture & Philosophy](#1-high-level-architecture--philosophy)
2. [Visual Execution Flowchart](#2-visual-execution-flowchart)
3. [The 6 Profiles: Layman Guide & Step Matrix](#3-the-6-profiles-layman-guide--step-matrix)
4. [Safety, Invariants & Disaster Recovery](#4-safety-invariants--disaster-recovery)
5. [Core Utilities & Helper Subsystem Pseudocode](#5-core-utilities--helper-subsystem-pseudocode)
6. [Step-by-Step Subsystem Pseudocode](#6-step-by-step-subsystem-pseudocode)
   - [Step 1: DNF Configuration (`setup_dnf`)](#step-1-dnf-configuration-setup_dnf)
   - [Step 2: DNS Configuration (`setup_dns`)](#step-2-dns-configuration-setup_dns)
   - [Step 3: Power Management (`setup_power`)](#step-3-power-management-setup_power)
   - [Step 4: No-Sleep Settings (`setup_nosleep`)](#step-4-no-sleep-settings-setup_nosleep)
   - [Step 5: System Fonts (`setup_fonts`)](#step-5-system-fonts-setup_fonts)
   - [Step 6: ZSH Shell & Starship (`setup_shell`)](#step-6-zsh-shell--starship-setup_shell)
   - [Step 7: Browser & Multimedia Codecs (`setup_browser_multimedia`)](#step-7-browser--multimedia-codecs-setup_browser_multimedia)
   - [Step 8: COPR Packaging Isolation (`setup_copr`)](#step-8-copr-packaging-isolation-setup_copr)
   - [Step 9: GNOME Desktop Polish & GSConnect (`setup_gnome`)](#step-9-gnome-desktop-polish--gsconnect-setup_gnome)
   - [Step 10: Essential & Desktop Utilities (`setup_packages`)](#step-10-essential--desktop-utilities-setup_packages)
   - [Step 11: Developer Ecosystem & PostgreSQL 18 (`setup_dev`)](#step-11-developer-ecosystem--postgresql-18-setup_dev)
   - [Step 12: Code Editor Selection & Runner (`setup_editor`)](#step-12-code-editor-selection--runner-setup_editor)
   - [Step 13: Flatpak Applications (`setup_flatpaks`)](#step-13-flatpak-applications-setup_flatpaks)
   - [Step 14: Docker Container Engine (`setup_docker`)](#step-14-docker-container-engine-setup_docker)
   - [Step 15: KVM/QEMU Hardware Virtualization (`setup_kvm`)](#step-15-kvmqemu-hardware-virtualization-setup_kvm)
   - [Step 16: Pre-Driver Kernel Gate (`setup_pre_driver_reboot`)](#step-16-pre-driver-kernel-gate-setup_pre_driver_reboot)
   - [Step 17: GPU Driver Detection & Secure Boot MOK (`setup_drivers`)](#step-17-gpu-driver-detection--secure-boot-mok-setup_drivers)
   - [Step 18: Summary & Post-Install Guidance (`show_summary`)](#step-18-summary--post-install-guidance-show_summary)
7. [Main Orchestrator Loop Pseudocode](#7-main-orchestrator-loop-pseudocode)

---

## 1. High-Level Architecture & Philosophy

A fresh installation of Fedora Workstation is minimal by design. It lacks proprietary media codecs (due to patent licensing), third-party repositories, optimized shell prompts, developer compilers, container isolation rules, and hardware acceleration drivers for certain GPUs.

`setup.sh` is an **interactive orchestrator** designed around four foundational principles:

1. **Explicit Opt-In & Transparency:** Nothing happens silently. Every major subsystem prompts you (`[Y/n]` or `[y/N]`) before executing.
2. **Strict Idempotency:** The script tracks completed steps in `~/.config/fedora-setup/state.txt`. If you interrupt the script or reboot halfway through (such as for a kernel update), re-running the script picks up right where you left off.
3. **Zero Accidental Package Removals:** The script never runs blind removals or wildcards. Critical build headers (`kernel-devel-matched`, `xorg-x11-drv-nvidia-kmodsrc`, `gnome-boxes`, `android-tools`) are explicitly declared as top-level packages to prevent DNF dependency pruning.
4. **Automated Safety Backups:** Any modified user or system configuration file (`.zshrc`, `.bashrc`, `dnf.conf`, `MangoHud.conf`, `starship.toml`, `kitty.conf`) is automatically backed up to timestamped storage before alteration.

---

## 2. Visual Execution Flowchart

```mermaid
flowchart TD
    Start(["Launch ./setup.sh"]) --> ParseArgs["Parse CLI Flags<br/>(--dry-run, --profile, --force)"]
    ParseArgs --> SudoKeepAlive["Spawn Sudo Background Loop<br/>(Keeps credentials alive during builds)"]
    SudoKeepAlive --> Preflight{"Preflight Checks"}
    
    Preflight --> CheckVersions["Show Installed Versions (Optional)"]
    Preflight --> CheckBackup["Offer Restore from Previous Backup"]
    Preflight --> CheckNet["Verify Internet Connectivity"]
    Preflight --> CheckDisk["Verify ≥20GB Free Disk Space"]
    
    CheckDisk --> BuildStepList["Filter Step Sequence for Profile<br/>(minimal | dev | gaming | workstation | creator | full)"]
    BuildStepList --> StepLoop{"For each step in Profile"}
    
    StepLoop --> CheckState{"Step already completed<br/>in state.txt?"}
    CheckState -- Yes (No --force) --> SkipStep["Skip Step & Increment Counter"]
    SkipStep --> StepLoop
    
    CheckState -- No (or --force) --> UserPrompt{"Prompt User:<br/>'Run this step?'"}
    UserPrompt -- No --> MarkSkipped["Mark Step Skipped"]
    MarkSkipped --> StepLoop
    
    UserPrompt -- Yes --> RunStep["Execute Subsystem Function<br/>(Backup config files -> Apply changes)"]
    RunStep --> StepSuccess{"Execution Succeeded?"}
    StepSuccess -- Yes --> MarkDone["Record step in state.txt"]
    StepSuccess -- No --> LogWarning["Log Warning & Increment Failures"]
    
    MarkDone --> StepLoop
    LogWarning --> StepLoop
    
    StepLoop -- All Steps Finished --> Summary["Display Summary & Service Audit<br/>(TLP, Docker, NVIDIA, ZSH, VA-API)"]
    Summary --> End(["Exit 0 (System Ready 🚀)"])
```

---

## 3. The 6 Profiles: Layman Guide & Step Matrix

Depending on your workflow, you don't need every tool under the sun. You can choose a profile using `./setup.sh --profile=<name>`:

| Profile | Target Audience | Summary of Installed Features |
| :--- | :--- | :--- |
| **`minimal`** | Minimalists, Server/Cloud instances | DNF speedups, DNS, system fonts, ZSH + Starship, Brave browser, multimedia codecs, GPU drivers (opt-in). |
| **`dev`** | Software Engineers, DevOps | Minimal + Power tuning, No-Sleep, GNOME tools, compilers (GCC/Clang/Rust/Node/Python), PostgreSQL 18, Code Editor (Zed/Codium/Antigravity/Code), Docker Engine, KVM/QEMU, GPU drivers. |
| **`gaming`** | Gamers, Casual Desktop Users | Minimal + Power tuning, GNOME tools, Steam (H.264 unlocked), MangoHud overlay, ProtonPlus, Flatpaks, GPU drivers. |
| **`workstation`**| Daily Productive Workstation | Minimal + Power tuning, GNOME tools, Essential packages, Steam, Flatpaks, KVM/QEMU virtualization, GPU drivers. |
| **`creator`** | Streamers, Video Editors, Designers | Gaming + OBS Studio, V4L2 virtual camera loopback, GStreamer development stack, GTK4/Adwaita headers, KVM/QEMU, GPU drivers. |
| **`full`** | All-in-One Power Users *(Default)* | Everything across all profiles, plus COPR package repos (Scrcpy, Yazi) and Debian packaging tooling (`dpkg-dev`). |

### Step Execution Matrix

| Subsystem Function | `minimal` | `dev` | `gaming` | `workstation` | `creator` | `full` |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `setup_dnf` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `setup_dns` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `setup_power` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `setup_nosleep` | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |
| `setup_fonts` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `setup_shell` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `setup_browser_multimedia` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `setup_copr` | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| `setup_gnome` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `setup_packages` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `setup_dev` | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |
| `setup_editor` | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |
| `setup_flatpaks` | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| `setup_docker` | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ |
| `setup_kvm` | ❌ | ✅ | ❌ | ✅ | ✅ | ✅ |
| `setup_pre_driver_reboot` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `setup_drivers` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 4. Safety, Invariants & Disaster Recovery

### Non-Destructive Modularity
The script performs zero blind deletions. When replacing packages (such as swapping patent-restricted `mesa-va-drivers` with RPM Fusion's `mesa-va-drivers-freeworld`), DNF's `swap` command is used atomically.

### DNF Top-Level Package Registration Invariant
To prevent DNF's `clean_requirements_on_remove` mechanism from mistakenly treating vital kernel modules or virtualization binaries as orphaned sub-dependencies, the following packages are registered directly in top-level transaction lists:
- `kernel-devel-matched`: Matches kernel headers strictly to the active kernel architecture.
- `xorg-x11-drv-nvidia-kmodsrc`: NVIDIA kernel module source package required for building out-of-tree drivers.
- `gnome-boxes`: Virtual machine GUI desktop client.
- `android-tools`: Official ADB and Fastboot binaries.

### Rollback Engine
Every time a configuration file is touched, it is archived to `~/.config/fedora-setup-backups/YYYYMMDD_HHMMSS/`. Running `./setup.sh` offers an automatic option at the start to restore your system configurations directly from your latest backup.

---

## 5. Core Utilities & Helper Subsystem Pseudocode

```text
FUNCTION run(command_and_arguments):
    IF dry_run_mode IS True THEN:
        PRINT "[DRY-RUN] Would execute: command_and_arguments"
        RETURN 0
    ELSE:
        EXECUTE command_and_arguments
        RETURN exit_code
    END IF
END FUNCTION

FUNCTION run_sudo(command_and_arguments):
    IF dry_run_mode IS True THEN:
        PRINT "[DRY-RUN] Would execute: sudo command_and_arguments"
        RETURN 0
    ELSE:
        EXECUTE sudo command_and_arguments
        RETURN exit_code
    END IF
END FUNCTION

FUNCTION verify_checksum(target_file, expected_sha256):
    actual_sha256 = CALCULATE_SHA256(target_file)
    IF actual_sha256 EQUALS expected_sha256 THEN:
        PRINT "[OK] Checksum verified: target_file"
        RETURN 0
    ELSE:
        PRINT "[ERROR] Checksum mismatch for target_file!"
        PRINT "  Expected: " + expected_sha256
        PRINT "  Actual:   " + actual_sha256
        RETURN 1
    END IF
END FUNCTION

FUNCTION github_download(repo_owner_name, filename_regex_pattern, destination_path, fallback_url):
    api_url = "https://api.github.com/repos/" + repo_owner_name + "/releases/latest"
    json_response = FETCH_HTTP(api_url, timeout=10s)
    
    download_url = NULL
    IF json_response IS NOT NULL THEN:
        download_url = PARSE_ASSET_URL(json_response, filename_regex_pattern)
    END IF
    
    IF download_url IS NULL THEN:
        download_url = fallback_url
    END IF
    
    IF download_url IS NOT NULL THEN:
        DOWNLOAD_FILE(download_url, destination_path, timeout=120s)
        RETURN 0
    ELSE:
        RETURN 1
    END IF
END FUNCTION

FUNCTION backup_file(file_path):
    IF file_path EXISTS on disk THEN:
        IF dry_run_mode IS True THEN:
            PRINT "[DRY-RUN] Backup file_path to backup directory"
        ELSE:
            CREATE_DIRECTORY(backup_directory)
            COPY file_path TO backup_directory + "/" + BASENAME(file_path) + ".backup"
            PRINT "[INFO] Backed up: file_path"
        END IF
    END IF
END FUNCTION

FUNCTION restore_backups():
    latest_backup_dir = FIND_NEWEST_DIRECTORY("~/.config/fedora-setup-backups/")
    IF latest_backup_dir DOES NOT EXIST THEN:
        PRINT "[WARN] No previous backups found."
        RETURN 1
    END IF
    
    IF PROMPT_USER("Restore all files from latest backup?") IS False THEN:
        RETURN 0
    END IF
    
    FOR EACH file IN [".zshrc", ".bashrc", "/etc/dnf/dnf.conf", "MangoHud.conf", "starship.toml", "kitty.conf"]:
        backup_copy = latest_backup_dir + "/" + BASENAME(file) + ".backup"
        IF backup_copy EXISTS THEN:
            RESTORE_FILE(backup_copy, file)
            PRINT "[OK] Restored: file"
        END IF
    END FOR
    
    DELETE_FILE("~/.config/fedora-setup/state.txt")
    PRINT "[WARN] State file reset. All steps will re-evaluate on next run."
END FUNCTION
```

---

## 6. Step-by-Step Subsystem Pseudocode

### Step 1: DNF Configuration (`setup_dnf`)
**Layman Purpose:** Turbocharges Fedora's package manager by downloading up to 10 packages simultaneously, sets default confirmation to Yes, and connects your computer to RPM Fusion (free and non-free software repositories) and Flathub.

```text
FUNCTION setup_dnf():
    BACKUP "/etc/dnf/dnf.conf"
    
    IF dry_run_mode IS False THEN:
        REMOVE existing "# BEGIN fedora-setup" block from "/etc/dnf/dnf.conf"
        APPEND to "/etc/dnf/dnf.conf":
            max_parallel_downloads=10
            defaultyes=True
    END IF
    
    DETECT active Fedora release version (default: 44)
    INSTALL RPM Fusion Free & Non-Free repository RPMs
    ADD Flathub remote repository for Flatpak apps
    EXECUTE "dnf update -y --refresh --setopt=best=True"
    
    MARK_STEP_COMPLETE("setup_dnf")
END FUNCTION
```

---

### Step 2: DNS Configuration (`setup_dns`)
**Layman Purpose:** Replaces sluggish or censorship-prone ISP Domain Name System (DNS) servers with ultra-fast, encrypted privacy resolvers (Cloudflare `1.1.1.1` or Google `8.8.8.8`). Virtual container interfaces (Docker, Libvirt bridges) are safely ignored so internal development networking doesn't break.

```text
FUNCTION setup_dns():
    IF PROMPT_USER("Would you like to configure custom DNS?") IS False THEN:
        PRINT "[INFO] Keeping default ISP/DHCP DNS."
        RETURN 0
    END IF
    
    PROMPT user to select:
        [1] Cloudflare DNS (1.1.1.1, 1.0.0.1 / 2606:4700:4700::1111, 2606:4700:4700::1001)
        [2] Google DNS (8.8.8.8, 8.8.4.4 / 2001:4860:4860::8888, 2001:4860:4860::8844)
        [3] Skip
        
    FOR EACH active NetworkManager connection:
        IF connection IS a virtual bridge ("docker0", "virbr0", "lo", "veth") THEN:
            SKIP connection (preserve internal container subnet routing)
        ELSE:
            SET connection ipv4.ignore-auto-dns = yes
            SET connection ipv4.dns = selected_ipv4
            SET connection ipv6.ignore-auto-dns = yes
            SET connection ipv6.dns = selected_ipv6
            RELOAD network interface to activate new DNS immediately
        END IF
    END FOR
    
    MARK_STEP_COMPLETE("setup_dns")
END FUNCTION
```

---

### Step 3: Power Management (`setup_power`)
**Layman Purpose:** Helps laptop users configure battery saving. Warns about the trade-offs between TLP and Fedora's default `power-profiles-daemon`, allowing users to make an informed choice.

```text
FUNCTION setup_power():
    WARN user regarding TLP vs GNOME power-profiles-daemon trade-offs
    IF PROMPT_USER("Use TLP instead of GNOME power profiles?") IS False THEN:
        PRINT "[INFO] Keeping default power-profiles-daemon."
        RETURN 0
    END IF
    
    INSTALL "tlp" and "tlp-rdw"
    ENABLE "tlp.service"
    MASK "power-profiles-daemon.service" (prevents D-Bus power governor conflicts)
    
    CREATE systemd oneshot unit "/etc/systemd/system/tlp-autostart.service" to enforce TLP on boot
    START TLP power optimizer
    
    MARK_STEP_COMPLETE("setup_power")
END FUNCTION
```

---

### Step 4: No-Sleep Settings (`setup_nosleep`)
**Layman Purpose:** Stops your computer and login lockscreen (GDM) from going to sleep or suspending when plugged into AC power or running background compile jobs.

```text
FUNCTION setup_nosleep():
    # 1. Configure GDM Login Greeter (runs in isolated system dconf db)
    CREATE dconf profile "/etc/dconf/profile/gdm"
    WRITE "/etc/dconf/db/gdm.d/01-power":
        sleep-inactive-ac-timeout = 0
        sleep-inactive-ac-type = 'nothing'
        sleep-inactive-battery-timeout = 0
        sleep-inactive-battery-type = 'nothing'
    RUN "dconf update"
    
    # 2. Configure Active User Session
    FOR EACH power key in ["sleep-inactive-ac-timeout 0", "sleep-inactive-ac-type nothing", ...]:
        RUN "gsettings set org.gnome.settings-daemon.plugins.power <key> <value>"
    END FOR
    
    MARK_STEP_COMPLETE("setup_nosleep")
END FUNCTION
```

---

### Step 5: System Fonts (`setup_fonts`)
**Layman Purpose:** Installs Microsoft Core Fonts (Arial, Times New Roman, Calibri), Google Noto, DejaVu, and downloads the FiraCode Nerd Font for beautiful terminal ligatures and developer icons.

```text
FUNCTION setup_fonts():
    INSTALL Microsoft Core fonts compatibility RPM, Google Noto, DejaVu, and Liberation font families
    DOWNLOAD "FiraCode.zip" from GitHub release ("ryanoasis/nerd-fonts")
    EXTRACT fonts into "~/.local/share/fonts/"
    REBUILD font cache ("fc-cache -fv")
    
    CONFIGURE GNOME desktop monospace font to "FiraCode Nerd Font 11"
    CONFIGURE Ptyxis terminal font to "FiraCode Nerd Font 12"
    
    MARK_STEP_COMPLETE("setup_fonts")
END FUNCTION
```

---

### Step 6: ZSH Shell & Starship (`setup_shell`)
**Layman Purpose:** Upgrades your command line from plain Bash to an ultra-modern ZSH setup featuring the cross-shell Starship prompt, auto-suggestions, syntax highlighting, Tokyo Night Kitty terminal theme, and optional KKFetch CLI.

```text
FUNCTION setup_shell():
    INSTALL "zsh", "starship", "fontconfig", "git"
    
    CLONE "zsh-autosuggestions" (depth 1) into "~/.zsh/plugins/"
    CLONE "zsh-syntax-highlighting" (depth 1) into "~/.zsh/plugins/"
    
    DEPLOY custom "~/.config/starship.toml" (Tokyo Night styling, git status, language versions)
    DEPLOY "~/.zshrc" (history sharing, pager suppression, eza/bat aliases, git shortcuts)
    DEPLOY "~/.bashrc" fallback configuration
    
    IF PROMPT_USER("Install and configure Kitty terminal emulator?") IS True THEN:
        INSTALL "kitty"
        DEPLOY "~/.config/kitty/kitty.conf" (Tokyo Night colors, Fira Code ligatures, Wayland blur)
    END IF
    
    IF PROMPT_USER("Install KKFetch system info CLI (by Kushagra Kumar)?") IS True THEN:
        ENABLE Copr repository "kk376/kkfetch"
        INSTALL "kkfetch"
    END IF
    
    IF PROMPT_USER("Set ZSH as default shell?") IS True THEN:
        RUN "chsh -s $(which zsh)"
    END IF
    
    MARK_STEP_COMPLETE("setup_shell")
END FUNCTION
```

---

### Step 7: Browser & Multimedia Codecs (`setup_browser_multimedia`)
**Layman Purpose:** Installs Brave Browser with privacy shields, replaces restricted open-source media stubs with full FFmpeg, installs OpenH264, and configures PipeWire/WirePlumber for High-Definition Bluetooth audio (LDAC, AAC, aptX, SBC-XQ).

```text
FUNCTION setup_browser_multimedia():
    ADD official Brave Browser RPM repository and INSTALL "brave-browser"
    INSTALL "mozilla-openh264"
    
    # Replace restricted FFmpeg with full freeworld build
    RUN "dnf swap -y ffmpeg-free ffmpeg --allowerasing"
    RUN "dnf group upgrade -y multimedia sound-and-video"
    
    # Configure WirePlumber Bluetooth HD Audio
    WRITE "~/.config/wireplumber/wireplumber.conf.d/50-bluez.conf":
        Prioritize codecs: LDAC, AAC, aptX-HD, aptX, SBC-XQ
        Enable hardware volume controls
    RESTART "wireplumber.service" under user session
    
    MARK_STEP_COMPLETE("setup_browser_multimedia")
END FUNCTION
```

---

### Step 8: COPR Packaging Isolation (`setup_copr`)
**Layman Purpose:** Confined strictly to the `full` profile. Offers third-party COPR packages with clear descriptions and decision guidance before enabling repositories.

```text
FUNCTION setup_copr():
    DEFINED_COPRS = [
        ("zeno/scrcpy", "scrcpy", "Scrcpy Android Screen Mirroring", "Install if you mirror Android screens"),
        ("lihaohong/yazi", "yazi, plugins", "Yazi Terminal File Manager", "Install if you want terminal file navigation")
    ]
    
    FOR EACH (repo, packages, title, recommendation) IN DEFINED_COPRS:
        PRINT title + " - Recommendation: " + recommendation
        IF PROMPT_USER("Enable COPR repo '" + repo + "' and install " + title + "?") IS True THEN:
            ENABLE COPR repository repo
            INSTALL packages
        END IF
    END FOR
    
    MARK_STEP_COMPLETE("setup_copr")
END FUNCTION
```

---

### Step 9: GNOME Desktop Polish & GSConnect (`setup_gnome`)
**Layman Purpose:** Installs GNOME Tweaks, sets up GSConnect (seamless wireless sync with Android phones via KDE Connect protocol), opens the required firewall ports, and deploys clean transparent titlebar CSS for GTK3 and GTK4 apps.

```text
FUNCTION setup_gnome():
    INSTALL "gnome-tweaks", "gnome-shell-extension-gsconnect"
    
    IF firewalld is active THEN:
        OPEN firewall service "kdeconnect" permanently and reload firewall
    END IF
    
    DEPLOY transparent titlebar/headerbar styling to:
        "~/.config/gtk-3.0/gtk.css"
        "~/.config/gtk-4.0/gtk.css"
        
    MARK_STEP_COMPLETE("setup_gnome")
END FUNCTION
```

---

### Step 10: Essential & Desktop Utilities (`setup_packages`)
**Layman Purpose:** Installs a curated toolbox of developer and desktop essentials (compilers, archivers, Fastfetch, Android tools, Timeshift, VLC), configures MangoHud for gaming, and offers standalone utilities (Vesktop, Stirling-PDF, NVIDIA Broadcast).

```text
FUNCTION setup_packages():
    CORE_PACKAGES = [
        gcc, clang, fastfetch, make, cmake, cargo, maven, bat, eza,
        fd-find, ripgrep, fzf, zoxide, ruff, nodejs, python3,
        java-latest-openjdk, p7zip, ntfs-3g, gparted, timeshift, vlc,
        qbittorrent, wl-clipboard, neovim, android-tools, ...
    ]
    
    IF is_gaming_profile() THEN:
        ADD steam, mangohud
    END IF
    
    IF is_creator_profile() THEN:
        ADD obs-studio, v4l-utils, gtk4-devel, libadwaita-devel, gstreamer1-devel, ...
    END IF
    
    INSTALL CORE_PACKAGES via DNF
    
    IF is_gaming_profile() THEN:
        UNLOCK Steam H.264 hardware video decoding
        DEPLOY default gaming HUD configuration to "~/.config/MangoHud/MangoHud.conf"
    END IF
    
    PROMPT & INSTALL Vesktop (Discord client with Wayland screen-share audio)
    PROMPT & INSTALL Stirling-PDF (Offline local PDF Swiss Army Knife)
    
    IF is_creator_profile() AND NVIDIA GPU is present THEN:
        PROMPT & INSTALL NVIDIA Broadcast for Linux (AI noise removal & virtual camera)
    END IF
    
    MARK_STEP_COMPLETE("setup_packages")
END FUNCTION
```

---

### Step 11: Developer Ecosystem & PostgreSQL 18 (`setup_dev`)
**Layman Purpose:** Sets up low-level build tools, Clang/LLVM, optional Rust toolchain (`rustup`), 50GB compressed `ccache` compiler caching, Node.js Corepack (`pnpm`/`yarn`), Git global defaults (suppressing pagers), PostgreSQL 18 Database server from PGDG with automatic `initdb`, and pgAdmin 4 Desktop GUI.

```text
FUNCTION setup_dev():
    INSTALL meson, ninja-build, autoconf, gdb, valgrind, strace, git-lfs, python3-devel, openssl-devel, ...
    IF profile IS "full" THEN:
        INSTALL "dpkg-dev" (Debian packaging utilities)
    END IF
    
    IF PROMPT_USER("Install full Rust toolchain (rustup, clippy, rust-analyzer)?") IS True THEN:
        INSTALL rust, cargo, rustup, clippy, rust-analyzer
    END IF
    
    CONFIGURE ccache (50GB cache limit, compression enabled)
    ENABLE Node.js corepack ("corepack enable")
    CREATE Python symlinks in "~/.local/bin/python"
    
    CONFIGURE Git global defaults:
        core.pager = "cat"
        push.autoSetupRemote = true
        pull.rebase = true
        diff.colorMoved = "zebra"
        
    INSTALL PostgreSQL 18 from official PGDG repository:
        INSTALL postgresql18-server
        INITIALIZE database cluster ("/usr/pgsql-18/bin/postgresql-18-setup initdb")
        ENABLE & START "postgresql-18.service"
        EXPORT PATH to "/usr/pgsql-18/bin"
        
    INSTALL pgAdmin 4 Desktop GUI from official repo
    
    MARK_STEP_COMPLETE("setup_dev")
END FUNCTION
```

---

### Step 12: Code Editor Selection & Runner (`setup_editor`)
**Layman Purpose:** Lets you pick and auto-configure your primary code editor with modern fonts, autosave, Catppuccin Mocha theme, and includes an intelligent polyglot terminal code runner (`zed-run`).

```text
FUNCTION setup_editor():
    PROMPT user to choose primary editor:
        [1] Zed (Recommended)
        [2] VS Codium (FLOSS)
        [3] Google Antigravity IDE
        [4] VS Code (Proprietary / telemetry)
        [5] Skip
        
    CASE choice OF:
        1:  # Zed Editor
            INSTALL Zed via official installer
            DEPLOY "~/.config/zed/settings.json" (Catppuccin Mocha, FiraCode font, autosave)
            DEPLOY "~/.config/zed/keymap.json" (F5 / Ctrl+Alt+N to run current file)
            DEPLOY "~/.config/zed/tasks.json"
            DEPLOY "~/.local/bin/zed-run" (Polyglot runner for Python, Rust, C, C++, Go, JS, TS, Bash;
                                          traps Ctrl+C to drop into interactive shell instead of quitting)
        2:  # VS Codium
            IMPORT official GPG key & repo
            INSTALL "codium" and DEPLOY settings
        3:  # Google Antigravity IDE
            INSTALL Antigravity CLI/IDE via installer script
            DEPLOY editor settings
        4:  # VS Code
            ADD Microsoft repository, install "code", and DEPLOY settings
        5:  # Skip
            PRINT "[INFO] Skipped editor installation."
    END CASE
    
    MARK_STEP_COMPLETE("setup_editor")
END FUNCTION
```

---

### Step 13: Flatpak Applications (`setup_flatpaks`)
**Layman Purpose:** Installs sandbox-isolated desktop tools from Flathub: LocalSend (fast AirDrop alternative for local network file transfers), Mission Center (modern Task Manager), and ProtonPlus (Proton-GE compatibility tool manager for Steam games).

```text
FUNCTION setup_flatpaks():
    INSTALL from Flathub:
        - "org.localsend.localsend_app" (LocalSend)
        - "io.missioncenter.MissionCenter" (Mission Center)
        - "com.vysp3r.ProtonPlus" (ProtonPlus)
        
    MARK_STEP_COMPLETE("setup_flatpaks")
END FUNCTION
```

---

### Step 14: Docker Container Engine (`setup_docker`)
**Layman Purpose:** Installs Docker Engine, configures NetworkManager and Firewalld to ignore Docker's virtual bridge (`docker0`) so container networking never interferes with your system connections, adds your user to the `docker` group, and downloads Docker Compose v2.

```text
FUNCTION setup_docker():
    INSTALL "docker", "docker-cli", "moby-engine", "containerd"
    
    # Configure NetworkManager to leave docker0 unmanaged
    WRITE "/etc/NetworkManager/conf.d/10-docker.conf":
        unmanaged-devices=interface-name:docker0
    RESTART NetworkManager
    
    # Configure Firewalld to prevent forward/NAT rule wiping on reload
    SET "/etc/firewalld/firewalld.conf" IgnoreInterfaces=docker0
    RESTART firewalld
    
    ADD current user to "docker" group
    ENABLE & START "docker.service"
    
    DOWNLOAD & INSTALL Docker Compose v2 CLI plugin to "~/.docker/cli-plugins/docker-compose"
    
    MARK_STEP_COMPLETE("setup_docker")
END FUNCTION
```

---

### Step 15: KVM/QEMU Hardware Virtualization (`setup_kvm`)
**Layman Purpose:** Turns Fedora into an enterprise-grade virtual machine host using KVM/QEMU, sets up modern modular socket activation (`virtqemud.socket`), installs Virt-Manager and GNOME Boxes, downloads Windows VirtIO drivers, applies the `virtual-host` kernel tuning profile, and adds your user to the `libvirt` group.

```text
FUNCTION setup_kvm():
    VERIFY CPU virtualization support (Intel VT-x 'vmx' or AMD-V 'svm' in /proc/cpuinfo)
    
    IF PROMPT_USER("Install KVM/QEMU virtualization packages?") IS True THEN:
        INSTALL @virtualization, qemu-kvm, libvirt, virt-manager, gnome-boxes, guestfs-tools
    END IF
    
    IF PROMPT_USER("Configure modern socket activation?") IS True THEN:
        DISABLE legacy "libvirtd.service"
        ENABLE on-demand "virtqemud.socket"
    END IF
    
    OPEN firewalld service "libvirt"
    
    IF PROMPT_USER("Install VirtIO drivers for Windows VMs?") IS True THEN:
        ADD virtio-win repository and INSTALL "virtio-win"
    END IF
    
    APPLY tuned kernel performance profile: "tuned-adm profile virtual-host"
    ADD current user to "libvirt" group
    SET export LIBVIRT_DEFAULT_URI="qemu:///system" in "~/.bashrc" and "~/.zshrc"
    
    PRINT detailed post-reboot storage ACL & pool setup commands
    
    MARK_STEP_COMPLETE("setup_kvm")
END FUNCTION
```

---

### Step 16: Pre-Driver Kernel Gate (`setup_pre_driver_reboot`)
**Layman Purpose:** Compares the running Linux kernel version against the newly installed kernel version. If an update was installed during Step 1, out-of-tree GPU drivers (like NVIDIA `akmods`) could compile against the wrong kernel headers. This gate checkpoints your progress and offers a clean reboot before building drivers.

```text
FUNCTION setup_pre_driver_reboot():
    running_kernel = EXECUTE "uname -r"
    installed_kernel = QUERY latest installed "kernel-core" RPM version
    
    IF running_kernel DOES NOT EQUAL installed_kernel THEN:
        PRINT "[WARN] Kernel mismatch detected!"
        PRINT "  Running:   " + running_kernel
        PRINT "  Installed: " + installed_kernel
        PRINT "A reboot is recommended before compiling GPU drivers."
        
        IF PROMPT_USER("Reboot now?") IS True THEN:
            MARK_STEP_COMPLETE("setup_pre_driver_reboot")
            RUN "sudo reboot"
            EXIT 0
        ELSE:
            PRINT "[WARN] Continuing without reboot. Driver modules may compile against stale kernel."
        END IF
    ELSE:
        PRINT "[INFO] Running kernel matches installed kernel. No reboot needed."
    END IF
    
    MARK_STEP_COMPLETE("setup_pre_driver_reboot")
END FUNCTION
```

---

### Step 17: GPU Driver Detection & Secure Boot MOK (`setup_drivers`)
**Layman Purpose:** Inspects your hardware PCIe bus and laptop chassis. Installs Intel VA-API drivers for Intel GPUs, Mesa freeworld drivers for AMD GPUs, and the proprietary NVIDIA driver stack (`akmod-nvidia`, CUDA, `v4l2loopback`). For UEFI Secure Boot users, it walks you through importing your MOK signing key so drivers load flawlessly without disabling Secure Boot.

```text
FUNCTION setup_drivers():
    DETECT system chassis ("hostnamectl chassis")
    DETECT presence of NVIDIA, AMD, and Intel GPUs via "lspci"
    
    # 1. Intel GPU Acceleration
    IF Intel GPU detected THEN:
        INSTALL "intel-media-driver" (Broadwell Gen8 and newer VA-API decoding)
    END IF
    
    # 2. AMD GPU Acceleration
    IF AMD GPU detected THEN:
        SWAP "mesa-va-drivers" FOR "mesa-va-drivers-freeworld"
        SWAP "mesa-vdpau-drivers" FOR "mesa-vdpau-drivers-freeworld"
    END IF
    
    # 3. NVIDIA GPU Driver & Secure Boot
    IF NVIDIA GPU detected THEN:
        INSTALL akmods, akmod-nvidia, kernel-devel-matched, xorg-x11-drv-nvidia-kmodsrc,
                xorg-x11-drv-nvidia-cuda, libva-nvidia-driver, akmod-v4l2loopback, mokutil
                
        FORCE immediate kernel module compilation: "sudo akmods --force"
        
        IF chassis is laptop AND (Intel or AMD GPU also present) THEN:
            PRINT "[INFO] NVIDIA Optimus Hybrid Graphics detected."
        END IF
        
        DISPLAY comprehensive Secure Boot MOK Guide:
            - Explain local key generation ("sudo kmodgenca -a")
            - Explain key import ("sudo mokutil --import /etc/pki/akmods/certs/public_key.der")
            - Walk through blue MOK Manager enrollment screen on reboot
    END IF
    
    MARK_STEP_COMPLETE("setup_drivers")
END FUNCTION
```

---

### Step 18: Summary & Post-Install Guidance (`show_summary`)
**Layman Purpose:** Summarizes execution time, steps completed/skipped/failed, checks the status of core background services (TLP, Docker, NVIDIA, default shell), runs video acceleration tests, and gives you a clear list of what to do next.

```text
FUNCTION show_summary():
    CALCULATE total elapsed execution duration
    PRINT summary banner: completed, failed, and skipped step tallies
    
    AUDIT and PRINT status of core services:
        - TLP power service
        - Docker container daemon
        - NVIDIA driver loaded
        - ZSH active default shell
        
    IF PROMPT_USER("Verify hardware video acceleration?") IS True THEN:
        PRINT available FFmpeg H.264 encoders
        PRINT active VA-API driver profiles via "vainfo"
    END IF
    
    PRINT actionable next steps:
        1. Reboot system (applies Docker/libvirt groups & kernel drivers)
        2. Open a new terminal to enjoy ZSH + Starship prompt
        3. Review log file at /tmp/fedora-setup-*.log
        
    PRINT "System ready! 🚀"
END FUNCTION
```

---

## 7. Main Orchestrator Loop Pseudocode

```text
FUNCTION main(arguments):
    PARSE CLI flags:
        --dry-run / -n  -> Preview without making changes
        --profile=NAME  -> Select from minimal, dev, gaming, workstation, creator, full
        --force / -f    -> Re-run completed steps
        --help / -h     -> Show help and exit
        
    PRINT welcome banner and log file location
    
    IF PROMPT_USER("Show currently installed versions?") IS True THEN:
        DISPLAY installed versions of zsh, brave, zed, docker, steam, etc.
    END IF
    
    IF PROMPT_USER("Restore from previous backup?") IS True THEN:
        EXECUTE restore_backups()
        EXIT 0
    END IF
    
    IF dry_run_mode IS False THEN:
        VERIFY internet connectivity (ping Google & Cloudflare DNS)
        VERIFY ≥ 20GB free disk space in user home directory
        START background sudo authentication refresher loop
    END IF
    
    INITIALIZE state tracking file ("~/.config/fedora-setup/state.txt")
    FILTER master step list against active profile
    
    FOR EACH (function_name, step_title) IN filtered_steps:
        IF step_is_already_completed(function_name) AND force_rerun IS False THEN:
            PRINT "[INFO] Already completed: " + step_title + " (use --force to re-run)"
            INCREMENT completed_counter
            CONTINUE
        END IF
        
        IF PROMPT_USER("Run step: " + step_title + "?") IS True THEN:
            execute_result = EXECUTE function_name()
            IF execute_result IS SUCCESS THEN:
                IF dry_run_mode IS False THEN:
                    RECORD function_name in state.txt
                END IF
            ELSE:
                PRINT "[WARN] " + step_title + " encountered issues."
                INCREMENT failed_counter
            END IF
        ELSE:
            PRINT "[WARN] Skipped: " + step_title
            INCREMENT skipped_counter
        END IF
    END FOR
    
    EXECUTE show_summary()
    KILL background sudo refresher loop
    EXIT 0
END FUNCTION
```
