# Fedora 44 Post-Install: Complete Visual Flowchart & Logic Specification

This document provides a **complete visual flowchart and logic breakdown** of the Fedora 44 Post-Install Setup Script (`setup.sh`).

> [!TIP]
> **Looking for a friendly, non-technical walkthrough instead?**  
> Check out **[HOW_IT_WORKS.md](HOW_IT_WORKS.md)** for the plain-English story, "Before vs After" transformation, peace-of-mind safety rules, and beginner FAQ!

---

## Table of Contents

1. [Master Lifecycle Flowchart](#1-master-lifecycle-flowchart)
2. [Profile Selection & Routing Decision Tree](#2-profile-selection--routing-decision-tree)
3. [Subsystem Flowcharts (Step-by-Step)](#3-subsystem-flowcharts-step-by-step)
   - [Step 1: DNF5 & Repository Setup (`setup_dnf`)](#step-1-dnf5--repository-setup-setup_dnf)
   - [Step 2: DNS Configuration (`setup_dns`)](#step-2-dns-configuration-setup_dns)
   - [Step 3: Core CLI Utilities (`setup_cli_core`)](#step-3-core-cli-utilities-setup_cli_core)
   - [Step 4: Shell, Starship & Modern Terminal (`setup_shell`)](#step-4-shell-starship--modern-terminal-setup_shell)
   - [Step 5: System, Microsoft & Nerd Fonts (`setup_fonts`)](#step-5-system-microsoft--nerd-fonts-setup_fonts)
   - [Step 6: Multimedia Codecs & Dynamic PipeWire Audio (`setup_multimedia`)](#step-6-multimedia-codecs--dynamic-pipewire-audio-setup_multimedia)
   - [Step 7: GNOME Desktop Polish & GSConnect (`setup_gnome`)](#step-7-gnome-desktop-polish--gsconnect-setup_gnome)
   - [Step 8: Desktop Applications & Productivity (`setup_desktop_apps`)](#step-8-desktop-applications--productivity-setup_desktop_apps)
   - [Step 9: Power Policies & High-Performance ZRAM (`setup_power`)](#step-9-power-policies--high-performance-zram-setup_power)
   - [Step 10: Modular Development Toolchains (`setup_dev`)](#step-10-modular-development-toolchains-setup_dev)
   - [Step 11: Code Editor Suite & Polyglot Runner (`setup_editor`)](#step-11-code-editor-suite--polyglot-runner-setup_editor)
   - [Step 12: Docker Container Engine (`setup_docker`)](#step-12-docker-container-engine-setup_docker)
   - [Step 13: KVM/QEMU Hardware Virtualization (`setup_kvm`)](#step-13-kvmqemu-hardware-virtualization-setup_kvm)
   - [Step 14: Gaming Stack & Heroic (`setup_gaming`)](#step-14-gaming-stack--heroic-setup_gaming)
   - [Step 15: Creator & Streaming Suite (`setup_creator`)](#step-15-creator--streaming-suite-setup_creator)
   - [Step 16: Pre-Driver Kernel Gate (`setup_pre_driver_reboot`)](#step-16-pre-driver-kernel-gate-setup_pre_driver_reboot)
   - [Step 17: Multi-Vendor GPU Drivers & Secure Boot MOK (`setup_drivers`)](#step-17-multi-vendor-gpu-drivers--secure-boot-mok-setup_drivers)
   - [Summary & Health Check (`show_summary`)](#summary--health-check-show_summary)
4. [Idempotency, State & Rollback Flowchart](#4-idempotency-state--rollback-flowchart)

---

## 1. Master Lifecycle Flowchart

The high-level execution pipeline from CLI invocation (or curl pipe) to system readiness:

```mermaid
flowchart TD
    Start(["Launch ./setup.sh [OPTIONS] or curl | bash"]) --> ParseArgs["Parse CLI Flags<br/>(--dry-run, --profile, --dev-type, --yes, --force, --help)"]
    ParseArgs --> TrapSetup["Register Signal Traps<br/>(SIGINT, SIGTERM, EXIT -> cleanup)"]
    TrapSetup --> CheckDryRun{"Is Dry-Run Mode?"}
    
    CheckDryRun -- No --> SpawnSudo["Spawn Background Sudo Keep-Alive Loop<br/>(Prevents auth timeout during long builds)"]
    CheckDryRun -- Yes --> Preflight
    SpawnSudo --> Preflight
    
    subgraph Preflight ["Phase 1: Preflight Checks"]
        ShowVerPrompt{"Show Installed Versions? [y/N]"}
        ShowVerPrompt -- Yes --> ShowVersions["Query RPM & CLI tool versions"] --> RestorePrompt
        ShowVerPrompt -- No --> RestorePrompt
        
        RestorePrompt{"Restore from previous backup? [y/N]"}
        RestorePrompt -- Yes --> RestoreBackupEngine["Execute restore_backups()<br/>(Restore config files & wipe state.txt)"] --> ExitEarly(["Exit 0"])
        RestorePrompt -- No --> NetCheck
        
        NetCheck{"Internet Connected?<br/>(Ping 8.8.8.8 / 1.1.1.1)"}
        NetCheck -- No --> ExitNetFail(["Error: No Internet Connection -> Exit 1"])
        NetCheck -- Yes --> DiskCheck
        
        DiskCheck{"Free Disk Space >= 20GB?"}
        DiskCheck -- No --> LowDiskPrompt{"Low Disk Space Warning.<br/>Continue anyway? [y/N]"}
        LowDiskPrompt -- No --> ExitDiskFail(["Error: Aborting -> Exit 1"])
        LowDiskPrompt -- Yes --> FilterSteps
        DiskCheck -- Yes --> FilterSteps
    end

    subgraph StepOrchestration ["Phase 2: Profile Filtering & Step Loop"]
        FilterSteps["Filter Step Sequence for Profile<br/>(minimal | workstation | dev | gaming | creator | full)"]
        FilterSteps --> InitState["Initialize State Tracking File<br/>(~/.config/fedora-setup/state.txt)"]
        InitState --> LoopNext{"More steps in profile?"}
        
        LoopNext -- Yes --> CheckDone{"Step completed in state.txt<br/>AND NOT --force?"}
        CheckDone -- Yes --> StepSkippedDone["Log 'Already completed'<br/>Increment COMPLETED_STEPS"] --> LoopNext
        
        CheckDone -- No --> UserPrompt{"Prompt User:<br/>'Run this step? [Y/n]'"}
        UserPrompt -- No --> UserSkipped["Log 'Skipped'<br/>Increment SKIPPED_STEPS"] --> LoopNext
        
        UserPrompt -- Yes --> ExecuteStep["Execute Subsystem Function<br/>(Auto-backup configs -> Run commands)"]
        ExecuteStep --> StepResult{"Function succeeded?"}
        StepResult -- Yes --> MarkState["Write function name to state.txt<br/>Increment COMPLETED_STEPS"] --> LoopNext
        StepResult -- No --> LogStepWarn["Log Warning: 'Step had issues'<br/>Increment FAILED_STEPS"] --> LoopNext
    end

    LoopNext -->|"No (All steps finished)"| Summary

    subgraph PostSummary ["Phase 3: Health Audit & Next Steps"]
        Summary["Execute show_summary()<br/>(Display total time & pass/fail tallies)"]
        Summary --> ServiceAudit["Audit Active Services<br/>(TLP, Docker, NVIDIA, Default Shell)"]
        ServiceAudit --> HardwareTestPrompt{"Verify VA-API / H.264 Video Accel? [y/N]"}
        HardwareTestPrompt -- Yes --> RunVAInfo["Execute vainfo & ffmpeg -encoders"] --> ShowNextSteps
        HardwareTestPrompt -- No --> ShowNextSteps
        ShowNextSteps["Print Actionable Next Steps<br/>1. Reboot system (groups & drivers)<br/>2. Open new terminal (ZSH + Starship)<br/>3. Review log file in /tmp/"]
        ShowNextSteps --> KillSudo["Terminate Sudo Keep-Alive Loop"]
        KillSudo --> Finish(["System Ready! 🚀 (Exit 0)"])
    end
```

---

## 2. Profile Selection & Routing Decision Tree

```mermaid
flowchart TD
    UserSelect(["User selects Profile via Interactive Menu or --profile=<name> (Default: full)"]) --> SwitchProfile{Selected Profile}

    SwitchProfile -- minimal --> P_Min["minimal Profile<br/>(4 Steps: DNF, DNS, CLI Core, Shell & Terminal)"]
    SwitchProfile -- workstation --> P_Work["workstation Profile<br/>(11 Steps: Minimal + Fonts, Codecs, GNOME, Desktop Apps, Power, Pre-Driver Reboot, Drivers)"]
    SwitchProfile -- dev --> P_Dev["dev Profile<br/>(15 Steps: Workstation + Dev Stack, Editor, Docker, KVM)"]
    SwitchProfile -- gaming --> P_Gaming["gaming Profile<br/>(12 Steps: Workstation + Gaming Stack with Steam/MangoHud/Heroic)"]
    SwitchProfile -- creator --> P_Creator["creator Profile<br/>(12 Steps: Workstation + Creator Suite with OBS/V4L2/wf-recorder)"]
    SwitchProfile -- full --> P_Full["full Profile (Default)<br/>(All 17 Steps: Superset of Workstation + Dev + Gaming + Creator)"]

    P_Min --> MinOnly["Target: Minimalist headless/cloud systems or lean workstations"]
    P_Work --> WorkOnly["Target: Daily office and general desktop productivity"]
    P_Dev --> DevOnly["Target: Systems, Web, Android, and AI developers"]
    P_Gaming --> GameOnly["Target: Linux gamers, Discord users, multimedia consumers"]
    P_Creator --> CreatorOnly["Target: Streamers, video editors, audio engineers, Linux desktop creators"]
    P_Full --> FullOnly["Target: Power users wanting complete workstation, dev, and gaming suite"]
```

---

## 3. Subsystem Flowcharts (Step-by-Step)

### Step 1: DNF5 & Repository Setup (`setup_dnf`)

```mermaid
flowchart TD
    StartDNF(["Start setup_dnf()"]) --> BackupDNF["Backup /etc/dnf/dnf.conf to timestamped backup directory"]
    BackupDNF --> CheckDry{"Dry-Run Mode?"}
    
    CheckDry -- No --> CleanOld["Remove existing '# BEGIN fedora-setup' block from dnf.conf"]
    CleanOld --> AppendFast["Append to /etc/dnf/dnf.conf:<br/>max_parallel_downloads=10<br/>defaultyes=True"]
    AppendFast --> DetectVer
    CheckDry -- Yes --> LogDry1["Log dry-run simulation"] --> DetectVer
    
    DetectVer["Detect Fedora Version via %fedora RPM macro (Default: 44)"]
    DetectVer --> InstallRPMFusion["Install RPM Fusion Free & Nonfree Release RPMs<br/>(dnf install --setopt=best=True)"]
    InstallRPMFusion --> EnableOpenH264["Enable fedora-cisco-openh264 repository"]
    EnableOpenH264 --> AddFlathub["Add Flathub Remote Repository<br/>(flatpak remote-add --if-not-exists flathub)"]
    AddFlathub --> DNFUpdate["Execute atomic metadata refresh & update:<br/>dnf upgrade -y --refresh --setopt=best=True"]
    DNFUpdate --> PromptFeedback{"Configure sudo password feedback (asterisks)? [y/N]"}
    
    PromptFeedback -- Yes --> WriteFeedback["Create /etc/sudoers.d/pwfeedback<br/>(Defaults pwfeedback, mode 0440)"] --> EndDNF
    PromptFeedback -- No --> EndDNF(["Mark 'setup_dnf' completed in state.txt"])
```

---

### Step 2: DNS Configuration (`setup_dns`)

```mermaid
flowchart TD
    StartDNS(["Start setup_dns()"]) --> PromptDNS{"Configure Custom DNS Resolvers? [Y/n]"}
    
    PromptDNS -- No --> SkipDNS["Log 'Keeping DHCP/ISP default settings'"] --> EndDNS(["Mark completed / skipped"])
    
    PromptDNS -- Yes --> MenuDNS{"Select Provider:<br/>[1] Cloudflare (1.1.1.1 / 1.0.0.1)<br/>[2] Google (8.8.8.8 / 8.8.4.4)<br/>[3] Skip"}
    
    MenuDNS -- 1 / Default --> SetCloudflare["Set DNS_IPV4='1.1.1.1 1.0.0.1'<br/>DNS_IPV6='2606:4700:4700::1111 2606:4700:4700::1001'"] --> LoopConns
    MenuDNS -- 2 --> SetGoogle["Set DNS_IPV4='8.8.8.8 8.8.4.4'<br/>DNS_IPV6='2001:4860:4860::8888 2001:4860:4860::8844'"] --> LoopConns
    MenuDNS -- 3 --> SkipDNS
    
    LoopConns["Get active NetworkManager connections via nmcli"] --> ConnFilter{"Is connection virtual bridge?<br/>(docker0 | virbr | lo | veth | br-)"}
    
    ConnFilter -- Yes --> IgnoreVirtual["Skip virtual interface (Preserve container networking)"] --> NextConn
    ConnFilter -- No --> ApplyDNS["Apply DNS settings to connection:<br/>nmcli connection modify <conn> ipv4.ignore-auto-dns yes ipv4.dns <IP><br/>nmcli connection modify <conn> ipv6.ignore-auto-dns yes ipv6.dns <IP>"]
    ApplyDNS --> CycleConn["Cycle interface connection:<br/>nmcli connection down <conn> -> up <conn>"] --> NextConn
    
    NextConn{"More active connections?"} -- Yes --> LoopConns
    NextConn -- No --> EndDNS
```

---

### Step 3: Core CLI Utilities (`setup_cli_core`)

```mermaid
flowchart TD
    StartCLI(["Start setup_cli_core()"]) --> InstallCLIPkgs["Install Core CLI Package Suite:<br/>fastfetch, bat, eza, fd-find, ripgrep, fzf, zoxide,<br/>wget, curl, btop, duf, plocate, tree, compsize,<br/>unzip, unrar, p7zip, jq, vim, wl-clipboard, xclip, git, android-tools"]
    InstallCLIPkgs --> VerifyCLI["dnf install -y --skip-unavailable"]
    VerifyCLI --> EndCLI(["Mark completed in state.txt"])
```

---

### Step 4: Shell, Starship & Modern Terminal (`setup_shell`)

```mermaid
flowchart TD
    StartShell(["Start setup_shell()"]) --> InstallShellPkgs["Install ZSH, Fish, git, curl, fontconfig"]
    InstallShellPkgs --> ClonePlugins["Clone ZSH Plugins (v0.7.1 & 0.8.0 pinned tags):<br/>zsh-autosuggestions, zsh-syntax-highlighting"]
    ClonePlugins --> CheckShellProfile{"Profile category?"}
    
    CheckShellProfile -->|"dev or full"| ShellMenuPrompt["Interactive Default Shell Menu:<br/>1. Fish (Recommended)<br/>2. ZSH<br/>3. Bash<br/>4. Skip (current shell)"]
    ShellMenuPrompt --> DevEnvPrompt["Interactive Menu:<br/>Developer exports & aliases for chosen shell?<br/>1. Full developer environment<br/>2. Clean standard aliases only"]
    DevEnvPrompt --> StarshipPrompt["Interactive Option:<br/>Install and configure Starship prompt? [Y/n]"] --> DeployConfigs
    CheckShellProfile -->|"minimal, workstation, gaming, creator"| StdAliasesOnly["Skip shell menu, dev exports & Starship<br/>Prepare clean standard aliases (clear, ls, cat, less)"] --> DeployConfigs

    DeployConfigs["Deploy ~/.zshrc, ~/.bashrc, and ~/.config/fish/config.fish<br/>Deploy ~/.config/starship.toml if Starship enabled"] --> CheckTermProfile{"Is dev or full profile?"}

    CheckTermProfile -- No --> EndShell(["Mark completed"])
    CheckTermProfile -- Yes --> TerminalPrompt{"Install modern GPU terminal instead of stock Ptyxis? [Y/n]"}
    
    TerminalPrompt -- No --> EndShell
    TerminalPrompt -- Yes --> ChooseTerminal["Choose Terminal Emulator:<br/>1. Ghostty (Recommended)<br/>2. Kitty<br/>3. Alacritty"]
    ChooseTerminal --> InstallAndDeployTerm["Install package via DNF / Copr<br/>Ghostty: deploy clean tab ergonomics to ~/.config/ghostty/config.ghostty<br/>Kitty/Alacritty: deploy Tokyo Night styling"] --> EndShell
```

---

### Step 5: System, Microsoft & Nerd Fonts (`setup_fonts`)

```mermaid
flowchart TD
    StartFonts(["Start setup_fonts()"]) --> InstallBaseFonts["Install system fonts via DNF:<br/>dejavu, liberation, google-noto, google-carlito, google-caladea, fontconfig"]
    InstallBaseFonts --> DownloadMSCoreRPM["Download msttcore-fonts-installer RPM<br/>Verify SHA256 checksum & install"]
    DownloadMSCoreRPM --> ExtendedMSPrompt{"Install extended Microsoft Office fonts (Cambria, Aptos, Segoe UI)? [Y/n]"}
    
    ExtendedMSPrompt -- Yes --> CabExtract["Extract Cambria from PowerPointViewer.exe via cabextract<br/>Download Aptos font family to ~/.local/share/fonts/ms-fonts/"] --> DownloadFiraCode
    ExtendedMSPrompt -- No --> DownloadFiraCode
    
    DownloadFiraCode["Download FiraCode Nerd Font zip from GitHub releases<br/>(ryanoasis/nerd-fonts via github_download helper)"]
    DownloadFiraCode --> ExtractFont["Unzip fonts to ~/.local/share/fonts/ && rm /tmp/FiraCode.zip"]
    ExtractFont --> UpdateFontCache["Rebuild font cache: fc-cache -fv"]
    UpdateFontCache --> SetGNOMEFont["Configure Default Monospace Fonts:<br/>GNOME desktop -> 'FiraCode Nerd Font 11'<br/>Ptyxis terminal -> 'FiraCode Nerd Font 12'"]
    SetGNOMEFont --> EndFonts(["Mark completed"])
```

---

### Step 6: Multimedia Codecs & Dynamic PipeWire Audio (`setup_multimedia`)

```mermaid
flowchart TD
    StartMedia(["Start setup_multimedia()"]) --> SwapFFmpeg["Atomic FFmpeg Swap:<br/>dnf swap -y ffmpeg-free ffmpeg --allowerasing"]
    SwapFFmpeg --> InstallFreeworld["Install freeworld codecs:<br/>gstreamer1-plugins-bad-freeworld, gstreamer1-plugins-ugly, mozilla-openh264"]
    InstallFreeworld --> GroupInstall["Install multimedia group without weak dependencies:<br/>dnf group install -y --with-optional multimedia --setopt=install_weak_deps=False"]
    GroupInstall --> WriteAudioConfig["Deploy System-Wide Audio Optimization:<br/>/etc/wireplumber/wireplumber.conf.d/50-bluez.conf<br/>(LDAC, AAC, aptX-HD, SBC-XQ Hi-Fi codecs)"]
    WriteAudioConfig --> DisableGDM_BT["Disable Bluetooth in GDM greeter:<br/>/var/lib/gdm/.config/wireplumber/.../disable-bluetooth.conf"]
    DisableGDM_BT --> WritePipeWireClock["Configure PipeWire dynamic sample rates:<br/>/etc/pipewire/pipewire.conf.d/99-clock-rates.conf (44.1k to 192k)"]
    WritePipeWireClock --> RestartWirePlumber["Restart active user audio services (pipewire & wireplumber)"]
    RestartWirePlumber --> EndMedia(["Mark completed"])
```

---

### Step 7: GNOME Desktop Polish & GSConnect (`setup_gnome`)

```mermaid
flowchart TD
    StartGNOME(["Start setup_gnome()"]) --> InstallGNOMETools["Install gnome-tweaks, gsconnect, appindicator"]
    InstallGNOMETools --> CheckFirewall{"Is firewalld active?"}
    
    CheckFirewall -- Yes --> OpenKDEConnect["Open firewall service for GSConnect / KDE Connect:<br/>firewall-cmd --permanent --add-service=kdeconnect && reload"] --> TitlebarPrompt
    CheckFirewall -- No --> TitlebarPrompt
    
    TitlebarPrompt{"Apply transparent GTK3/GTK4 titlebar CSS? [Y/n]"}
    TitlebarPrompt -- Yes --> DeployGTKCSS["Deploy Transparent Titlebar & Headerbar CSS:<br/>Write ~/.config/gtk-3.0/gtk.css & ~/.config/gtk-4.0/gtk.css"] --> SetMutter
    TitlebarPrompt -- No --> SetMutter
    
    SetMutter["Set GNOME Mutter check-alive-timeout to 0 (Prevents 'App Not Responding' false alarms)"]
    SetMutter --> EndGNOME(["Mark completed"])
```

---

### Step 8: Desktop Applications & Productivity (`setup_desktop_apps`)

```mermaid
flowchart TD
    StartApps(["Start setup_desktop_apps()"]) --> AddBraveRepo["Add official Brave Browser RPM repo file"]
    AddBraveRepo --> InstallDesktopPkgs["Install desktop productivity packages via DNF:<br/>brave-browser, vlc, qbittorrent, telegram-desktop, timeshift, gparted, ntfs-3g, wmctrl"]
    InstallDesktopPkgs --> InstallFlatpaks["Install sandboxed desktop Flatpaks from Flathub:<br/>- org.localsend.localsend_app (LocalSend)<br/>- com.mattjakeman.ExtensionManager (Extension Manager)"]
    InstallFlatpaks --> PromptYazi{"Install Yazi file manager via Copr? [Y/n]"}
    
    PromptYazi -- Yes --> InstallYazi["Enable lihaohong/yazi Copr & install yazi with image preview tools"] --> PromptVesktop
    PromptYazi -- No --> PromptVesktop
    
    PromptVesktop{"Install Vesktop (Wayland Discord with screen audio)? [Y/n]"}
    PromptVesktop -- Yes --> InstallVesktop["Download Vesktop RPM from GitHub Releases via github_download & install via DNF"] --> PromptStirling
    PromptVesktop -- No --> PromptStirling
    
    PromptStirling{"Install Stirling-PDF (Offline Desktop PDF Suite)? [y/N]"}
    PromptStirling -- Yes --> InstallStirling["Download Stirling-PDF RPM & install via DNF"] --> EndApps(["Mark completed"])
    PromptStirling -- No --> EndApps
```

---

### Step 9: Power Policies & High-Performance ZRAM (`setup_power`)

```mermaid
flowchart TD
    StartPower(["Start setup_power()"]) --> CheckChassis{"Is Laptop Chassis?"}
    
    CheckChassis -- Yes --> PromptTLP{"Modern laptops perform best with Fedora native power-profiles-daemon.<br/>Replace with TLP anyway? [y/N]"}
    PromptTLP -- Yes --> InstallTLP["Install tlp, mask power-profiles-daemon, enable tlp.service"] --> PromptNoSleep
    PromptTLP -- No --> KeepPPD["Keep native power-profiles-daemon"] --> PromptNoSleep
    CheckChassis -- No --> LogDesktop["Desktop chassis detected: Skip TLP"] --> PromptNoSleep
    
    PromptNoSleep{"Disable auto-suspend when plugged into AC power? [Y/n]"}
    PromptNoSleep -- Yes --> ConfigNoSleep["Configure AC no-sleep in /etc/dconf/db/gdm.d/01-power<br/>and user session gsettings (Preserves battery sleep safety)"] --> PromptZRAM
    PromptNoSleep -- No --> PromptZRAM
    
    PromptZRAM{"Apply high-performance ZRAM tuning? [Y/n]"}
    PromptZRAM -- Yes --> DeployZRAM["Deploy drop-in /etc/systemd/zram-generator.conf.d/10-zram.conf:<br/>zram-size = ram<br/>compression-algorithm = zstd<br/><br/>Deploy kernel sysctl /etc/sysctl.d/99-zram.conf:<br/>vm.swappiness = 180<br/>vm.watermark_boost_factor = 0<br/>vm.watermark_scale_factor = 125<br/>vm.page-cluster = 0<br/><br/>Remove legacy monolithic /etc/systemd/zram-generator.conf (with backup)<br/>sysctl --system && restart systemd-zram-setup@zram0"] --> EndPower(["Mark completed"])
    PromptZRAM -- No --> EndPower
```

---

### Step 10: Modular Development Toolchains (`setup_dev`)

```mermaid
flowchart TD
    StartDev(["Start setup_dev()"]) --> SelectGenres["Evaluate dev genres: --dev-type or interactive<br/>(systems, web, android, ai, all)"]
    SelectGenres --> BuildPkgs["Build dev_pkgs list:<br/>Base: meson, ninja, automake, gdb, valgrind, strace, git-lfs, python3-devel<br/>Systems: gcc, clang, llvm, make, cmake<br/>Web: nodejs, npm<br/>Android: java-latest-openjdk, maven<br/>AI: python3-pip, virtualenv, wheel, ruff, uv"]
    BuildPkgs --> InstallDevPkgs["Execute: dnf install -y --skip-unavailable dev_pkgs"]
    
    InstallDevPkgs --> CheckSystemsGenre{"Has 'systems' genre?"}
    CheckSystemsGenre -- Yes --> RustPrompt{"Install full Rust toolchain (rustup, clippy, rust-analyzer)? [Y/n]"}
    RustPrompt -- Yes --> InstallRust["Install rust, cargo, rustup, clippy, rust-analyzer"] --> CcachePrompt
    RustPrompt -- No --> CcachePrompt
    
    CcachePrompt{"Install and configure ccache (50GB compressed)? [Y/n]"}
    CcachePrompt -- Yes --> InstallCcache["Install ccache & configure 50GB limit with compression"] --> CheckAndroidGenre
    CcachePrompt -- No --> CheckAndroidGenre
    CheckSystemsGenre -- No --> CheckAndroidGenre
    
    CheckAndroidGenre{"Has 'android' genre?"}
    CheckAndroidGenre -- Yes --> AndroidStudioPrompt{"Install Android Studio (via Flathub)? [Y/n]"}
    AndroidStudioPrompt -- Yes --> InstallAndroidStudio["flatpak install flathub com.google.AndroidStudio"] --> ScrcpyPrompt
    AndroidStudioPrompt -- No --> ScrcpyPrompt
    ScrcpyPrompt{"Install Scrcpy low-latency screen mirror via Copr? [Y/n]"}
    ScrcpyPrompt -- Yes --> InstallScrcpy["Enable zeno/scrcpy Copr & install scrcpy"] --> CheckAIGenre
    ScrcpyPrompt -- No --> CheckAIGenre
    CheckAndroidGenre -- No --> CheckAIGenre
    
    CheckAIGenre{"Has 'ai' genre?"}
    CheckAIGenre -- Yes --> CheckCompute{"Probe GPU for Compute:"}
    CheckCompute -- NVIDIA --> CudaPrompt{"Install NVIDIA CUDA development libraries? [Y/n]"}
    CudaPrompt -- Yes --> InstallCuda["dnf install xorg-x11-drv-nvidia-cuda-devel"] --> CheckWebGenre
    CudaPrompt -- No --> CheckWebGenre
    CheckCompute -- AMD --> ROCmPrompt{"Install AMD ROCm OpenCL / HIP? [Y/n]"}
    ROCmPrompt -- Yes --> InstallROCm["dnf install rocm-opencl rocm-hip"] --> CheckWebGenre
    ROCmPrompt -- No --> CheckWebGenre
    CheckCompute -- Intel --> IntelComputePrompt{"Install Intel Compute Runtime (oneAPI / Level Zero)? [Y/n]"}
    IntelComputePrompt -- Yes --> InstallIntelCompute["dnf install intel-compute-runtime intel-opencl level-zero"] --> CheckWebGenre
    IntelComputePrompt -- No --> CheckWebGenre
    CheckAIGenre -- No --> CheckWebGenre
    
    CheckWebGenre{"Has 'web' genre?"}
    CheckWebGenre -- Yes --> EnableCorepack["Enable Node.js Corepack (yarn/pnpm)"] --> PythonSymlink
    CheckWebGenre -- No --> PythonSymlink
    
    PythonSymlink["Create ~/.local/bin/python symlink"] --> GitWorkflowPrompt{"Configure Git workflow defaults (autoSetupRemote, pull.rebase, diff.colorMoved)? [y/N]"}
    GitWorkflowPrompt -- Yes --> BackupAndSetGit["Backup ~/.gitconfig<br/>git config --global push.autoSetupRemote true<br/>git config --global pull.rebase true<br/>git config --global diff.colorMoved zebra"] --> PGPrompt
    GitWorkflowPrompt -- No --> PGPrompt
    
    PGPrompt{"Install and initialize PostgreSQL Server? [y/N]"}
    PGPrompt -- Yes --> InstallPG["Architecture-aware install (PGDG repo for x86_64, Fedora native for others)<br/>Initialize DB & enable postgresql service"] --> EndDev(["Mark completed"])
    PGPrompt -- No --> EndDev
```

---

### Step 11: Code Editor Suite & Polyglot Runner (`setup_editor`)

```mermaid
flowchart TD
    StartEditor(["Start setup_editor()"]) --> EditorMenu{"Choose Primary Code Editor:<br/>[1] Zed (Recommended)<br/>[2] VS Codium (FLOSS)<br/>[3] Google Antigravity IDE<br/>[4] VS Code (Proprietary)<br/>[5] Skip"}
    
    EditorMenu -- 1: Zed --> InstallZed["Install Zed via official installer script"]
    InstallZed --> DeployZedSettings["Deploy ~/.config/zed/settings.json<br/>(Catppuccin Mocha, FiraCode font, autosave)"]
    DeployZedSettings --> DeployZedKeymap["Deploy ~/.config/zed/keymap.json<br/>(F5 / Ctrl+Alt+N to run current file)"]
    DeployZedKeymap --> DeployZedRunner["Deploy polyglot ~/.local/bin/zed-run:<br/>Auto-detects Python, Rust, C, C++, Go, JS, TS, Bash"] --> EndEditor(["Mark completed"])
    
    EditorMenu -- 2: Codium --> AddCodiumRepo["Import official GPG key & add VSCodium repo"]
    AddCodiumRepo --> InstallCodium["Install codium & deploy settings.json"] --> EndEditor
    
    EditorMenu -- 3: Antigravity --> InstallAgy["Install Antigravity CLI/IDE via official script"]
    InstallAgy --> DeployAgySettings["Deploy ~/.config/antigravity/settings.json"] --> EndEditor
    
    EditorMenu -- 4: VS Code --> AddMSCodeRepo["Add Microsoft VS Code repo & install 'code'"]
    AddMSCodeRepo --> DeployCodeSettings["Deploy ~/.config/Code/User/settings.json"] --> EndEditor
    
    EditorMenu -- 5: Skip --> SkipEditor["Log 'Skipped code editor installation'"] --> EndEditor
```

---

### Step 12: Docker Container Engine (`setup_docker`)

```mermaid
flowchart TD
    StartDocker(["Start setup_docker()"]) --> InstallDockerPkgs["Install Docker packages:<br/>docker, docker-cli, moby-engine, containerd, freerdp"]
    InstallDockerPkgs --> IgnoreNM["Configure NetworkManager to ignore docker0 interface:<br/>Write /etc/NetworkManager/conf.d/10-docker.conf"]
    IgnoreNM --> IgnoreFirewall["Configure Firewalld to preserve container NAT rules:<br/>Set IgnoreInterfaces=docker0 in /etc/firewalld/firewalld.conf"]
    IgnoreFirewall --> AddDockerGroup["Add current user to 'docker' group<br/>(sudo usermod -aG docker $USER)"]
    AddDockerGroup --> StartDockerService["systemctl enable containerd.service<br/>systemctl reset-failed docker (if failed)<br/>systemctl enable --now docker"]
    StartDockerService --> InstallDockerCompose["Architecture-aware compose plugin:<br/>Download docker-compose CLI plugin from GitHub releases<br/>Install to ~/.docker/cli-plugins/docker-compose"]
    InstallDockerCompose --> EndDocker(["Mark completed"])
```

---

### Step 13: KVM/QEMU Hardware Virtualization (`setup_kvm`)

```mermaid
flowchart TD
    StartKVM(["Start setup_kvm()"]) --> CheckCPU{"CPU Virtualization Supported?<br/>(vmx or svm in /proc/cpuinfo)"}
    
    CheckCPU -- No --> PromptNoVT{"VT-x/AMD-V not detected.<br/>Continue anyway? [y/N]"}
    PromptNoVT -- No --> SkipKVM["Log 'KVM skipped - no virtualization support'"] --> EndKVM(["Mark completed"])
    PromptNoVT -- Yes --> InstallKVMPkgs
    CheckCPU -- Yes --> InstallKVMPkgs
    
    InstallKVMPkgs["Install Virtualization Packages:<br/>@virtualization, qemu-kvm, libvirt, virt-manager, gnome-boxes, guestfs-tools"]
    InstallKVMPkgs --> ModularSockets["Switch to Modular Socket Activation:<br/>systemctl disable --now libvirtd.service<br/>systemctl enable --now virtqemud.socket"]
    ModularSockets --> OpenFirewallLibvirt["Configure Firewalld:<br/>firewall-cmd --permanent --add-service=libvirt && reload"]
    OpenFirewallLibvirt --> VirtIOPrompt{"Install VirtIO Windows VM Drivers? [y/N]"}
    
    VirtIOPrompt -- Yes --> InstallVirtIO["Add virtio-win repo & install virtio-win RPM"] --> TunedProfile
    VirtIOPrompt -- No --> TunedProfile
    
    TunedProfile["Apply Kernel Virtualization Profile:<br/>tuned-adm profile virtual-host"]
    TunedProfile --> AddLibvirtGroup["Add user to 'libvirt' group<br/>Export LIBVIRT_DEFAULT_URI='qemu:///system' in ~/.bashrc and ~/.zshrc"]
    AddLibvirtGroup --> PostRebootInstructions["Display post-reboot storage pool ACLs & virsh verification commands"]
    PostRebootInstructions --> EndKVM
```

---

### Step 14: Gaming Stack & Heroic (`setup_gaming`)

```mermaid
flowchart TD
    StartGaming(["Start setup_gaming()"]) --> InstallGamePkgs["Install gaming packages via DNF:<br/>steam, mangohud, gamemode, vulkan-tools"]
    InstallGamePkgs --> UnlockSteamH264["Unlock Steam H.264 video codec decoding:<br/>steam-devices & mozilla-openh264"]
    UnlockSteamH264 --> DeployMangoHudConf["Deploy ~/.config/MangoHud/MangoHud.conf<br/>(GPU/CPU temps, core clocks, FPS, frame timing, 3-column table, 24px font)"]
    DeployMangoHudConf --> PromptHeroic{"Install Heroic Games Launcher (Epic, GOG, Amazon) via Flathub? [Y/n]"}
    
    PromptHeroic -- Yes --> InstallHeroic["Install com.heroicgameslauncher.hgl Flatpak<br/>Pre-create ~/.var/app/.../Prefixes directory"] --> EndGaming(["Mark completed"])
    PromptHeroic -- No --> EndGaming
```

---

### Step 15: Creator & Streaming Suite (`setup_creator`)

```mermaid
flowchart TD
    StartCreator(["Start setup_creator()"]) --> InstallCreatorPkgs["Install creator packages via DNF:<br/>obs-studio, akmod-v4l2loopback, v4l2loopback, v4l-utils, wf-recorder, pulseaudio-utils, gstreamer1-devel"]
    InstallCreatorPkgs --> CheckNVGPU{"NVIDIA GPU detected?"}
    
    CheckNVGPU -- Yes --> PromptNVBroadcast{"Install NVIDIA Broadcast for Linux (AI noise removal & virtual camera)? [y/N]"}
    PromptNVBroadcast -- Yes --> InstallNVB["Clone Hkshoonya/nvidia-broadcast-linux into ~/.local/share/nvidia-broadcast-linux<br/>Execute ./install.sh --runtime cuda"] --> EndCreator(["Mark completed"])
    PromptNVBroadcast -- No --> EndCreator
    CheckNVGPU -- No --> EndCreator
```

---

### Step 16: Pre-Driver Kernel Gate (`setup_pre_driver_reboot`)

```mermaid
flowchart TD
    StartGate(["Start setup_pre_driver_reboot()"]) --> QueryRunningKernel["Get running kernel: uname -r"]
    QueryRunningKernel --> QueryInstalledKernel["Get newest installed kernel RPM version:<br/>rpm -q --last kernel-core kernel"]
    QueryInstalledKernel --> CompareKernels{"Running Kernel == Installed Kernel?"}
    
    CompareKernels -- Yes --> MatchLog["Log 'Running kernel matches installed kernel - no reboot needed'"] --> EndGate(["Mark completed"])
    
    CompareKernels -- No --> WarnMismatch["Log Warning: Kernel mismatch detected!<br/>Building out-of-tree GPU drivers (akmods) would target wrong headers."]
    WarnMismatch --> PromptReboot{"Reboot now to boot into latest kernel? [Y/n]"}
    
    PromptReboot -- Yes --> MarkDoneAndReboot["Mark 'setup_pre_driver_reboot' completed in state.txt<br/>Execute: sudo reboot<br/>Exit 0"]
    PromptReboot -- No --> WarnSkipReboot["Log Warning: Driver modules may build against stale kernel."] --> EndGate
```

---

### Step 17: Multi-Vendor GPU Drivers & Secure Boot MOK (`setup_drivers`)

```mermaid
flowchart TD
    StartDrivers(["Start setup_drivers()"]) --> ProbeHardware["Hardware Globals Probed at Startup:<br/>- Chassis: hostnamectl chassis (IS_LAPTOP)<br/>- GPUs: lspci (HAS_NVIDIA, HAS_AMD, HAS_INTEL)"]
    
    ProbeHardware --> CheckIntel{"Intel GPU present?"}
    CheckIntel -- Yes --> InstallIntel["Install intel-media-driver and libva-intel-driver"] --> CheckAMD
    CheckIntel -- No --> CheckAMD
    
    CheckAMD{"AMD GPU present?"}
    CheckAMD -- Yes --> InstallAMD["Swap Mesa drivers for freeworld builds:<br/>dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld<br/>dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld"] --> CheckNVIDIA
    CheckAMD -- No --> CheckNVIDIA
    
    CheckNVIDIA{"NVIDIA GPU present?"}
    CheckNVIDIA -- Yes --> InstallNVIDIA["Install NVIDIA Driver Stack:<br/>akmod-nvidia, akmods, kernel-devel-matched, xorg-x11-drv-nvidia-cuda, libva-nvidia-driver, mokutil"]
    InstallNVIDIA --> BuildModules["Force module compilation: sudo akmods --force"]
    BuildModules --> CheckOptimus{"Is Laptop Chassis AND Hybrid GPU present (AMD/Intel + NVIDIA)?"}
    
    CheckOptimus -- Yes --> PromptOptimus{"Hybrid Optimus detected.<br/>External display warning: setting iGPU priority saves battery but may affect dGPU-wired monitors.<br/>Set iGPU as primary Vulkan device? [Y/n]"}
    PromptOptimus -- Yes --> ConfigVulkan["Write /etc/environment.d/10-vulkan-hybrid.conf:<br/>VK_LOADER_DRIVERS_SELECT=*radeon* or *intel*"] --> SecureBootGuide
    PromptOptimus -- No --> LogOptimusSkip["Preserve default Vulkan device discovery"] --> SecureBootGuide
    CheckOptimus -- No --> SecureBootGuide
    
    SecureBootGuide["Display Comprehensive Secure Boot & MOK Guide:<br/>1. Key generation (kmodgenca -a)<br/>2. Key import (mokutil --import public_key.der)<br/>3. Blue MOK Manager enrollment walkthrough on reboot"] --> EndDrivers(["Mark completed"])
    CheckNVIDIA -- No --> EndDrivers
```

---

### Summary & Health Check (`show_summary`)

```mermaid
flowchart TD
    StartSummary(["Start show_summary()"]) --> CalcTime["Calculate total execution duration (minutes & seconds)"]
    CalcTime --> PrintTallies["Display summary banner:<br/>- Completed steps tally<br/>- Failed steps tally<br/>- Skipped steps tally"]
    PrintTallies --> CheckServices["Audit System Service Status:<br/>- TLP (systemctl is-active tlp)<br/>- Docker (systemctl is-active docker)<br/>- NVIDIA Driver (nvidia-smi check)<br/>- Active Login Shell (from /etc/passwd)"]
    CheckServices --> VideoTestPrompt{"Verify hardware video acceleration? [y/N]"}
    
    VideoTestPrompt -- Yes --> RunVideoTests["Query FFmpeg H.264 encoders<br/>Query VA-API profiles via vainfo"] --> PrintNextSteps
    VideoTestPrompt -- No --> PrintNextSteps
    
    PrintNextSteps["Display Actionable Next Steps:<br/>1. Reboot system (applies Docker/libvirt groups & kernel drivers)<br/>2. Open new terminal (Fish/ZSH + Starship prompt)<br/>3. Review detailed log in /tmp/fedora-setup-*.log"]
    PrintNextSteps --> EndSummary(["System Ready! 🚀"])
```

---

## 4. Idempotency, State & Rollback Flowchart

How `setup.sh` handles step resumption, failure recovery, and backup restoration:

```mermaid
flowchart TD
    subgraph StateResumption ["Resumption & Interruption Lifecycle"]
        Launch["User runs ./setup.sh or curl | bash"] --> ReadStateFile["Read ~/.config/fedora-setup/state.txt"]
        ReadStateFile --> StepEvaluator{"For each step in active profile"}
        
        StepEvaluator --> StepInState{"Step function name<br/>present in state.txt?"}
        StepInState -->|"Yes (No --force)"| SkipToNext["Skip step execution<br/>(Zero redundant downloads or writes)"]
        SkipToNext --> StepEvaluator
        StepInState -->|"No (Or --force passed)"| PromptAndRun["Prompt user & Execute step function"]
        
        PromptAndRun --> StepSuccess{"Execution succeeded?"}
        StepSuccess -->|"Yes"| AppendState["Append function name to state.txt"]
        AppendState --> StepEvaluator
        StepSuccess -->|"No"| PreserveState["Do NOT write to state.txt<br/>(Step will re-prompt on next run)"]
        PreserveState --> StepEvaluator
    end

    subgraph RollbackEngine ["Disaster Recovery & Rollback Subsystem"]
        RunRestore["User launches ./setup.sh -> Confirms 'Restore from previous backup?'"] --> ScanBackups["Find newest directory in ~/.config/fedora-setup-backups/YYYYMMDD_HHMMSS/"]
        ScanBackups --> FoundBackups{"Backup directory found?"}
        FoundBackups -->|"No"| LogNoBackup["Log 'No backups found' -> Exit 1"]
        FoundBackups -->|"Yes"| ConfirmRestore{"Restore all files from this timestamp? [y/N]"}
        
        ConfirmRestore -->|"Yes"| RestoreFiles["Restore original files from timestamped backup:<br/>- ~/.zshrc<br/>- ~/.bashrc<br/>- ~/.gitconfig<br/>- /etc/dnf/dnf.conf<br/>- /etc/systemd/zram-generator.conf<br/>- ~/.config/MangoHud/MangoHud.conf<br/>- ~/.config/starship.toml<br/>- ~/.config/ghostty/config.ghostty<br/>- ~/.config/kitty/kitty.conf<br/>- ~/.config/alacritty/alacritty.toml"]
        RestoreFiles --> WipeState["Delete ~/.config/fedora-setup/state.txt<br/>(Resets state so future runs re-evaluate cleanly)"]
        WipeState --> ExitRestore(["Exit 0 (System restored to original clean state)"])
        ConfirmRestore -->|"No"| CancelRestore(["Cancel restore"])
    end
```
