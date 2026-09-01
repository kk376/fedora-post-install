# Fedora 44 Post-Install: Complete Visual Flowchart & Logic Specification

This document provides a **complete visual flowchart and logic breakdown** of the Fedora 44 Post-Install Setup Script (`setup.sh`).

It is designed for humans to visually trace every decision diamond, hardware detection path, package transaction, user prompt, and configuration state transition from launch to completion.

---

## Table of Contents

1. [Master Lifecycle Flowchart](#1-master-lifecycle-flowchart)
2. [Profile Selection & Routing Decision Tree](#2-profile-selection--routing-decision-tree)
3. [Subsystem Flowcharts (Step-by-Step)](#3-subsystem-flowcharts-step-by-step)
   - [Step 1: DNF & Repository Setup (`setup_dnf`)](#step-1-dnf--repository-setup-setup_dnf)
   - [Step 2: DNS Configuration (`setup_dns`)](#step-2-dns-configuration-setup_dns)
   - [Step 3: Power Optimization & TLP (`setup_power`)](#step-3-power-optimization--tlp-setup_power)
   - [Step 4: No-Sleep & Greeter Policies (`setup_nosleep`)](#step-4-no-sleep--greeter-policies-setup_nosleep)
   - [Step 5: System Fonts & Nerd Fonts (`setup_fonts`)](#step-5-system-fonts--nerd-fonts-setup_fonts)
   - [Step 6: ZSH Shell, Starship & Terminal (`setup_shell`)](#step-6-zsh-shell-starship--terminal-setup_shell)
   - [Step 7: Browser, Codecs & Bluetooth HD Audio (`setup_browser_multimedia`)](#step-7-browser-codecs--bluetooth-hd-audio-setup_browser_multimedia)
   - [Step 8: COPR Packaging Isolation (`setup_copr`)](#step-8-copr-packaging-isolation-setup_copr)
   - [Step 9: GNOME Desktop Polish & GSConnect (`setup_gnome`)](#step-9-gnome-desktop-polish--gsconnect-setup_gnome)
   - [Step 10: Essential Packages & Gaming (`setup_packages`)](#step-10-essential-packages--gaming-setup_packages)
   - [Step 11: Developer Ecosystem & PostgreSQL 18 (`setup_dev`)](#step-11-developer-ecosystem--postgresql-18-setup_dev)
   - [Step 12: Code Editor Suite & Polyglot Runner (`setup_editor`)](#step-12-code-editor-suite--polyglot-runner-setup_editor)
   - [Step 13: Flatpak Applications (`setup_flatpaks`)](#step-13-flatpak-applications-setup_flatpaks)
   - [Step 14: Docker Container Engine (`setup_docker`)](#step-14-docker-container-engine-setup_docker)
   - [Step 15: KVM/QEMU Hardware Virtualization (`setup_kvm`)](#step-15-kvmqemu-hardware-virtualization-setup_kvm)
   - [Step 16: Pre-Driver Kernel Gate (`setup_pre_driver_reboot`)](#step-16-pre-driver-kernel-gate-setup_pre_driver_reboot)
   - [Step 17: GPU Driver Detection & Secure Boot MOK (`setup_drivers`)](#step-17-gpu-driver-detection--secure-boot-mok-setup_drivers)
   - [Step 18: Summary & Service Health Check (`show_summary`)](#step-18-summary--service-health-check-show_summary)
4. [Idempotency, State & Rollback Flowchart](#4-idempotency-state--rollback-flowchart)

---

## 1. Master Lifecycle Flowchart

The high-level execution pipeline from CLI invocation to system readiness:

```mermaid
flowchart TD
    Start(["Launch ./setup.sh [OPTIONS]"]) --> ParseArgs["Parse CLI Flags<br/>(--dry-run, --profile, --force, --help)"]
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
        
        DiskCheck{"Free Disk Space ≥ 20GB?"}
        DiskCheck -- No --> LowDiskPrompt{"Low Disk Space Warning.<br/>Continue anyway? [y/N]"}
        LowDiskPrompt -- No --> ExitDiskFail(["Error: Aborting -> Exit 1"])
        LowDiskPrompt -- Yes --> FilterSteps
        DiskCheck -- Yes --> FilterSteps
    end

    subgraph StepOrchestration ["Phase 2: Profile Filtering & Step Loop"]
        FilterSteps["Filter Step Sequence for Profile<br/>(minimal | dev | gaming | workstation | creator | full)"]
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

    LoopNext -- No (All steps finished) --> Summary

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
    UserSelect(["User selects Profile via --profile=<name> (Default: full)"]) --> SwitchProfile{Selected Profile}

    SwitchProfile -- minimal --> P_Min["minimal Profile<br/>(7 Steps: DNF, DNS, Fonts, Shell, Browser/Codecs, Pre-Driver Reboot, Drivers)"]
    SwitchProfile -- dev --> P_Dev["dev Profile<br/>(15 Steps: Minimal + Power, No-Sleep, GNOME, Packages, Dev Tools, Editor, Docker, KVM, Drivers)"]
    SwitchProfile -- gaming --> P_Gaming["gaming Profile<br/>(11 Steps: Minimal + Power, GNOME, Packages with Steam/MangoHud, Flatpaks, Drivers)"]
    SwitchProfile -- workstation --> P_Work["workstation Profile<br/>(12 Steps: Gaming + Essential Packages + KVM/QEMU Virtualization + Drivers)"]
    SwitchProfile -- creator --> P_Creator["creator Profile<br/>(12 Steps: Gaming + OBS Studio + V4L2 Virtual Camera + GStreamer + KVM + Drivers)"]
    SwitchProfile -- full --> P_Full["full Profile (Default)<br/>(All 17 Steps: Includes COPR Repositories & Debian dpkg-dev Packaging)"]

    P_Min --> CoreOnly["Target: Minimalist server, container host, or lean desktop"]
    P_Dev --> DevOnly["Target: Software engineers, backend/web developers, DevOps"]
    P_Gaming --> GameOnly["Target: Linux gamers, Discord users, multimedia consumers"]
    P_Work --> WorkOnly["Target: Daily productive desktop with VMs & development capability"]
    P_Creator --> CreatorOnly["Target: Streamers, video editors, audio engineers, Linux desktop creators"]
    P_Full --> FullOnly["Target: Power users wanting every utility and repo configured"]
```

---

## 3. Subsystem Flowcharts (Step-by-Step)

### Step 1: DNF & Repository Setup (`setup_dnf`)

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
    InstallRPMFusion --> AddFlathub["Add Flathub Remote Repository<br/>(flatpak remote-add --if-not-exists flathub)"]
    AddFlathub --> DNFUpdate["Execute atomic metadata refresh & update:<br/>dnf update -y --refresh --setopt=best=True"]
    DNFUpdate --> EndDNF(["Mark 'setup_dnf' completed in state.txt"])
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

### Step 3: Power Optimization & TLP (`setup_power`)

```mermaid
flowchart TD
    StartPower(["Start setup_power()"]) --> WarnTLP["Display warning: TLP vs GNOME Power Profiles Daemon"]
    WarnTLP --> PromptTLP{"Use TLP instead of GNOME power profiles? [y/N]"}
    
    PromptTLP -- No --> KeepPPD["Keep default power-profiles-daemon (No changes made)"] --> EndPower(["Mark completed"])
    
    PromptTLP -- Yes --> InstallTLP["Install TLP packages:<br/>sudo dnf install -y tlp tlp-rdw"]
    InstallTLP --> MaskPPD["Enable tlp.service & Mask power-profiles-daemon.service<br/>(Prevents D-Bus power governor conflicts)"]
    MaskPPD --> DeployUnit["Create /etc/systemd/system/tlp-autostart.service<br/>(Forces TLP apply after multi-user.target boot)"]
    DeployUnit --> ReloadStart["systemctl daemon-reload && systemctl enable tlp-autostart<br/>sudo tlp start"]
    ReloadStart --> EndPower
```

---

### Step 4: No-Sleep & Greeter Policies (`setup_nosleep`)

```mermaid
flowchart TD
    StartNoSleep(["Start setup_nosleep()"]) --> GreeterDconf["Configure GDM Login Greeter Profile:<br/>Write /etc/dconf/profile/gdm (user-db, system-db:gdm)"]
    GreeterDconf --> WriteGDMKeyfile["Write /etc/dconf/db/gdm.d/01-power:<br/>sleep-inactive-ac-timeout=0<br/>sleep-inactive-ac-type='nothing'<br/>sleep-inactive-battery-timeout=0<br/>sleep-inactive-battery-type='nothing'"]
    WriteGDMKeyfile --> UpdateDconf["Execute 'sudo dconf update'"]
    UpdateDconf --> UserSessionGsettings["Configure Active User Session via gsettings:<br/>org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0<br/>org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'"]
    UserSessionGsettings --> EndNoSleep(["Mark completed"])
```

---

### Step 5: System Fonts & Nerd Fonts (`setup_fonts`)

```mermaid
flowchart TD
    StartFonts(["Start setup_fonts()"]) --> InstallBaseFonts["Install system fonts via DNF:<br/>mscore-fonts, dejavu, liberation, google-noto, google-carlito, fontconfig"]
    InstallBaseFonts --> DownloadMSCoreRPM["Download msttcore-fonts-installer RPM & install without digest check"]
    DownloadMSCoreRPM --> DownloadFiraCode["Download FiraCode Nerd Font zip from GitHub releases<br/>(ryanoasis/nerd-fonts via github_download helper)"]
    DownloadFiraCode --> ExtractFont["Unzip fonts to ~/.local/share/fonts/ && rm /tmp/FiraCode.zip"]
    ExtractFont --> UpdateFontCache["Rebuild font cache: fc-cache -fv"]
    UpdateFontCache --> SetGNOMEFont["Configure Default Monospace Fonts:<br/>GNOME desktop -> 'FiraCode Nerd Font 11'<br/>Ptyxis terminal -> 'FiraCode Nerd Font 12'"]
    SetGNOMEFont --> EndFonts(["Mark completed"])
```

---

### Step 6: ZSH Shell, Starship & Terminal (`setup_shell`)

```mermaid
flowchart TD
    StartShell(["Start setup_shell()"]) --> InstallZSH["Install ZSH, Starship, git, curl, fontconfig"]
    InstallZSH --> ClonePlugins["Clone ZSH Plugins (depth 1):<br/>- zsh-autosuggestions -> ~/.zsh/plugins/<br/>- zsh-syntax-highlighting -> ~/.zsh/plugins/"]
    ClonePlugins --> DeployStarshipToml["Deploy ~/.config/starship.toml<br/>(Tokyo Night prompt, git status symbols, language versions)"]
    DeployStarshipToml --> CheckDevProfile{"Is dev or full profile?"}
    
    CheckDevProfile -- Yes --> DeployDevZshrc["Deploy Developer ~/.zshrc<br/>(NVM, EDITOR=nvim, PAGER=cat, dev aliases)"] --> DeployBashrc
    CheckDevProfile -- No --> DeployStdZshrc["Deploy Standard ~/.zshrc<br/>(PAGER=cat, eza/bat aliases, Starship init)"] --> DeployBashrc
    
    DeployBashrc["Sync ~/.bashrc with Starship & pager suppression"] --> KittyPrompt{"Install and configure Kitty terminal emulator? [Y/n]"}
    
    KittyPrompt -- Yes --> InstallKitty["Install 'kitty' via DNF"]
    InstallKitty --> DeployKittyConf["Deploy ~/.config/kitty/kitty.conf<br/>(Tokyo Night palette, Fira Code ligatures, Wayland blur, keybindings)"] --> KKFetchPrompt
    KittyPrompt -- No --> KKFetchPrompt
    
    KKFetchPrompt{"Install KKFetch system info CLI (by Kushagra Kumar)? [Y/n]"}
    KKFetchPrompt -- Yes --> EnableKKFetchCopr["Enable Copr repo 'kk376/kkfetch' & install kkfetch"] --> ChshPrompt
    KKFetchPrompt -- No --> ChshPrompt
    
    ChshPrompt{"Set ZSH as default shell? [Y/n]"}
    ChshPrompt -- Yes --> RunChsh["Execute: chsh -s $(which zsh)"] --> EndShell(["Mark completed"])
    ChshPrompt -- No --> EndShell
```

---

### Step 7: Browser, Codecs & Bluetooth HD Audio (`setup_browser_multimedia`)

```mermaid
flowchart TD
    StartMedia(["Start setup_browser_multimedia()"]) --> AddBraveRepo["Add official Brave Browser RPM repo file"]
    AddBraveRepo --> InstallBrave["Install brave-browser and mozilla-openh264"]
    InstallBrave --> SwapFFmpeg["Atomic FFmpeg Swap:<br/>dnf swap -y ffmpeg-free ffmpeg --allowerasing"]
    SwapFFmpeg --> GroupUpgrade["Upgrade multimedia groups:<br/>dnf group upgrade -y multimedia sound-and-video"]
    GroupUpgrade --> WriteWirePlumber["Deploy WirePlumber Bluetooth Config:<br/>~/.config/wireplumber/wireplumber.conf.d/50-bluez.conf<br/>(Prioritize LDAC, AAC, aptX, SBC-XQ; enable hardware volume)"]
    WriteWirePlumber --> RestartWirePlumber["Restart user wireplumber.service"]
    RestartWirePlumber --> EndMedia(["Mark completed"])
```

---

### Step 8: COPR Packaging Isolation (`setup_copr`)

```mermaid
flowchart TD
    StartCopr(["Start setup_copr() (full profile only)"]) --> LoopCoprs["Iterate through curated COPR tool list"]
    
    LoopCoprs --> PromptScrcpy{"Scrcpy - Android Screen Mirroring (zeno/scrcpy):<br/>Install? [Y/n]"}
    PromptScrcpy -- Yes --> EnableScrcpy["Enable Copr repo 'zeno/scrcpy' & install scrcpy"] --> PromptYazi
    PromptScrcpy -- No --> PromptYazi
    
    PromptYazi{"Yazi - Terminal File Manager with Previews (lihaohong/yazi):<br/>Install? [Y/n]"}
    PromptYazi -- Yes --> EnableYazi["Enable Copr repo 'lihaohong/yazi' & install yazi, 7zip, resvg, etc."] --> EndCopr(["Mark completed"])
    PromptYazi -- No --> EndCopr
```

---

### Step 9: GNOME Desktop Polish & GSConnect (`setup_gnome`)

```mermaid
flowchart TD
    StartGNOME(["Start setup_gnome()"]) --> InstallGNOMETools["Install gnome-tweaks & gnome-shell-extension-gsconnect"]
    InstallGNOMETools --> CheckFirewall{"Is firewalld active?"}
    
    CheckFirewall -- Yes --> OpenKDEConnect["Open firewall service for GSConnect / KDE Connect:<br/>firewall-cmd --permanent --add-service=kdeconnect && reload"] --> DeployGTKCSS
    CheckFirewall -- No --> DeployGTKCSS
    
    DeployGTKCSS["Deploy Transparent Titlebar & Headerbar CSS:<br/>Write ~/.config/gtk-3.0/gtk.css & ~/.config/gtk-4.0/gtk.css"]
    DeployGTKCSS --> EndGNOME(["Mark completed"])
```

---

### Step 10: Essential Packages & Gaming (`setup_packages`)

```mermaid
flowchart TD
    StartPkgs(["Start setup_packages()"]) --> BuildPkgList["Build core essential package list<br/>(Compilers, Fastfetch, archivers, VLC, Neovim, android-tools, etc.)"]
    
    BuildPkgList --> CheckGamingProfile{"Is gaming profile?"}
    CheckGamingProfile -- Yes --> AddGamingPkgs["Add steam, mangohud to install list"] --> CheckCreatorProfile
    CheckGamingProfile -- No --> CheckCreatorProfile
    
    CheckCreatorProfile{"Is creator profile?"}
    CheckCreatorProfile -- Yes --> AddCreatorPkgs["Add obs-studio, v4l-utils, gtk4-devel, libadwaita-devel, gstreamer1-devel"] --> InstallAllPkgs
    CheckCreatorProfile -- No --> InstallAllPkgs
    
    InstallAllPkgs["Install all packages via DNF (--skip-unavailable)"] --> UnlockSteamH264{"Gaming profile active?"}
    
    UnlockSteamH264 -- Yes --> UnlockH264["Execute Steam H.264 codec unlock (steam://unlockh264/)"]
    UnlockH264 --> DeployMangoHudConf["Deploy ~/.config/MangoHud/MangoHud.conf<br/>(GPU/CPU temps, FPS, frame timing, clean 3-column table)"] --> PromptVesktop
    UnlockSteamH264 -- No --> PromptVesktop
    
    PromptVesktop{"Vesktop (Discord Client with Wayland Screen Audio):<br/>Install? [Y/n]"}
    PromptVesktop -- Yes --> InstallVesktop["Download Vesktop RPM from GitHub Releases & install via DNF"] --> PromptStirling
    PromptVesktop -- No --> PromptStirling
    
    PromptStirling{"Stirling-PDF (Offline Desktop PDF Suite):<br/>Install? [Y/n]"}
    PromptStirling -- Yes --> InstallStirling["Download Stirling-PDF RPM & install via DNF"] --> CheckNVBroadcast
    PromptStirling -- No --> CheckNVBroadcast
    
    CheckNVBroadcast{"Creator profile AND NVIDIA GPU present?"}
    CheckNVBroadcast -- Yes --> PromptNVBroadcast{"NVIDIA Broadcast for Linux (AI Noise & Video FX):<br/>Install? [Y/n]"}
    PromptNVBroadcast -- Yes --> InstallNVB["Git clone (depth 1) & run install.sh --runtime cuda"] --> EndPkgs(["Mark completed"])
    PromptNVBroadcast -- No --> EndPkgs
    CheckNVBroadcast -- No --> EndPkgs
```

---

### Step 11: Developer Ecosystem & PostgreSQL 18 (`setup_dev`)

```mermaid
flowchart TD
    StartDev(["Start setup_dev()"]) --> InstallDevTools["Install low-level developer tools:<br/>meson, ninja, automake, gdb, valgrind, strace, git-lfs, python3-devel, openssl-devel"]
    InstallDevTools --> CheckFullProfile{"Is profile 'full'?"}
    
    CheckFullProfile -- Yes --> InstallDpkgDev["Install dpkg-dev (Debian packaging)"] --> RustPrompt
    CheckFullProfile -- No --> RustPrompt
    
    RustPrompt{"Install full Rust toolchain (rustup, clippy, rust-analyzer)? [Y/n]"}
    RustPrompt -- Yes --> InstallRust["Install rust, cargo, rustup, clippy, rust-analyzer"] --> ConfigCcache
    RustPrompt -- No --> ConfigCcache
    
    ConfigCcache["Configure ccache:<br/>Max size: 50GB, compression: true, cache_dir: ~/.ccache"]
    ConfigCcache --> EnableCorepack["Enable Node.js Corepack (yarn/pnpm)"]
    EnableCorepack --> PythonSymlinks["Create Python symlinks in ~/.local/bin/python"]
    PythonSymlinks --> GitDefaults["Configure Git global defaults:<br/>core.pager=cat, push.autoSetupRemote=true, pull.rebase=true"]
    GitDefaults --> InstallPG18["Install PostgreSQL 18 Server from official PGDG repository"]
    InstallPG18 --> InitPG18{"Is /var/lib/pgsql/18/data initialized?"}
    
    InitPG18 -- No --> RunInitDB["Run: /usr/pgsql-18/bin/postgresql-18-setup initdb"] --> EnablePGService
    InitPG18 -- Yes --> EnablePGService
    
    EnablePGService["systemctl enable --now postgresql-18<br/>Export PATH in /etc/profile.d/pgsql18.sh"]
    EnablePGService --> InstallPGAdmin["Install pgAdmin 4 Desktop GUI from official repo"]
    InstallPGAdmin --> EndDev(["Mark completed"])
```

---

### Step 12: Code Editor Suite & Polyglot Runner (`setup_editor`)

```mermaid
flowchart TD
    StartEditor(["Start setup_editor()"]) --> EditorMenu{"Choose Primary Code Editor:<br/>[1] Zed (Recommended)<br/>[2] VS Codium (FLOSS)<br/>[3] Google Antigravity IDE<br/>[4] VS Code (Proprietary)<br/>[5] Skip"}
    
    EditorMenu -- 1: Zed --> InstallZed["Install Zed via official installer script"]
    InstallZed --> DeployZedSettings["Deploy ~/.config/zed/settings.json<br/>(Catppuccin Mocha, FiraCode font, autosave)"]
    DeployZedSettings --> DeployZedKeymap["Deploy ~/.config/zed/keymap.json<br/>(F5 / Ctrl+Alt+N to run current file)"]
    DeployZedKeymap --> DeployZedRunner["Deploy polyglot ~/.local/bin/zed-run:<br/>Auto-detects Python, Rust, C, C++, Go, JS, TS, Bash;<br/>Traps Ctrl+C to drop into interactive terminal"] --> EndEditor(["Mark completed"])
    
    EditorMenu -- 2: Codium --> AddCodiumRepo["Import official GPG key & add VSCodium repo"]
    AddCodiumRepo --> InstallCodium["Install codium & deploy settings.json"] --> EndEditor
    
    EditorMenu -- 3: Antigravity --> InstallAgy["Install Antigravity CLI/IDE via official script"]
    InstallAgy --> DeployAgySettings["Deploy ~/.config/antigravity/settings.json"] --> EndEditor
    
    EditorMenu -- 4: VS Code --> AddMSCodeRepo["Add Microsoft VS Code repo & install 'code'"]
    AddMSCodeRepo --> DeployCodeSettings["Deploy ~/.config/Code/User/settings.json"] --> EndEditor
    
    EditorMenu -- 5: Skip --> SkipEditor["Log 'Skipped code editor installation'"] --> EndEditor
```

---

### Step 13: Flatpak Applications (`setup_flatpaks`)

```mermaid
flowchart TD
    StartFlatpaks(["Start setup_flatpaks()"]) --> InstallApps["Install sandboxed desktop Flatpaks from Flathub:<br/>- org.localsend.localsend_app (LocalSend)<br/>- io.missioncenter.MissionCenter (Mission Center)<br/>- com.vysp3r.ProtonPlus (ProtonPlus)"]
    InstallApps --> ShowProtonPlusInfo["Display ProtonPlus / Proton GE configuration tips"]
    ShowProtonPlusInfo --> EndFlatpaks(["Mark completed"])
```

---

### Step 14: Docker Container Engine (`setup_docker`)

```mermaid
flowchart TD
    StartDocker(["Start setup_docker()"]) --> InstallDockerPkgs["Install Docker packages:<br/>docker, docker-cli, moby-engine, containerd, freerdp"]
    InstallDockerPkgs --> IgnoreNM["Configure NetworkManager to ignore docker0 interface:<br/>Write /etc/NetworkManager/conf.d/10-docker.conf"]
    IgnoreNM --> IgnoreFirewall["Configure Firewalld to preserve container NAT rules:<br/>Set IgnoreInterfaces=docker0 in /etc/firewalld/firewalld.conf"]
    IgnoreFirewall --> AddDockerGroup["Add current user to 'docker' group<br/>(sudo usermod -aG docker $USER)"]
    AddDockerGroup --> StartDockerService["systemctl enable containerd.service<br/>systemctl reset-failed docker (if failed)<br/>systemctl enable --now docker"]
    StartDockerService --> InstallDockerCompose["Download Docker Compose v2 CLI plugin from GitHub releases<br/>Install to ~/.docker/cli-plugins/docker-compose"]
    InstallDockerCompose --> EndDocker(["Mark completed"])
```

---

### Step 15: KVM/QEMU Hardware Virtualization (`setup_kvm`)

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
    OpenFirewallLibvirt --> VirtIOPrompt{"Install VirtIO Windows VM Drivers? [Y/n]"}
    
    VirtIOPrompt -- Yes --> InstallVirtIO["Add virtio-win repo & install virtio-win RPM"] --> TunedProfile
    VirtIOPrompt -- No --> TunedProfile
    
    TunedProfile["Apply Kernel Virtualization Profile:<br/>tuned-adm profile virtual-host"]
    TunedProfile --> AddLibvirtGroup["Add user to 'libvirt' group<br/>Export LIBVIRT_DEFAULT_URI='qemu:///system' in ~/.bashrc and ~/.zshrc"]
    AddLibvirtGroup --> PostRebootInstructions["Display post-reboot storage pool ACLs & virsh verification commands"]
    PostRebootInstructions --> EndKVM
```

---

### Step 16: Pre-Driver Kernel Gate (`setup_pre_driver_reboot`)

```mermaid
flowchart TD
    StartGate(["Start setup_pre_driver_reboot()"]) --> QueryRunningKernel["Get running kernel: uname -r"]
    QueryRunningKernel --> QueryInstalledKernel["Get newest installed kernel RPM version:<br/>rpm -q --last kernel-core kernel"]
    QueryInstalledKernel --> CompareKernels{"Running Kernel == Installed Kernel?"}
    
    CompareKernels -- Yes --> MatchLog["Log 'Running kernel matches installed kernel — no reboot needed'"] --> EndGate(["Mark completed"])
    
    CompareKernels -- No --> WarnMismatch["Log Warning: Kernel mismatch detected!<br/>Building out-of-tree GPU drivers (akmods) would target wrong headers."]
    WarnMismatch --> PromptReboot{"Reboot now to boot into latest kernel? [Y/n]"}
    
    PromptReboot -- Yes --> MarkDoneAndReboot["Mark 'setup_pre_driver_reboot' completed in state.txt<br/>Execute: sudo reboot<br/>Exit 0"]
    PromptReboot -- No --> WarnSkipReboot["Log Warning: Driver modules may build against stale kernel."] --> EndGate
```

---

### Step 17: GPU Driver Detection & Secure Boot MOK (`setup_drivers`)

```mermaid
flowchart TD
    StartDrivers(["Start setup_drivers()"]) --> CheckMinProfile{"Is profile 'minimal'?"}
    
    CheckMinProfile -- Yes --> PromptMinDrivers{"Configure GPU drivers? [y/N]"}
    PromptMinDrivers -- No --> SkipMinDrivers["Log 'Skipping GPU driver setup'"] --> EndDrivers(["Mark completed"])
    PromptMinDrivers -- Yes --> ProbeHardware
    CheckMinProfile -- No --> ProbeHardware
    
    ProbeHardware["Probe Hardware Subsystem:<br/>- Chassis: hostnamectl chassis<br/>- GPUs: lspci | grep -Ei 'VGA|3D|Display' (NVIDIA, AMD, Intel)"]
    
    ProbeHardware --> CheckIntel{"Intel GPU present?"}
    CheckIntel -- Yes --> InstallIntel["Install intel-media-driver (Broadwell Gen8+ VA-API decode)"] --> CheckAMD
    CheckIntel -- No --> CheckAMD
    
    CheckAMD{"AMD GPU present?"}
    CheckAMD -- Yes --> InstallAMD["Swap Mesa drivers for freeworld builds:<br/>dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld<br/>dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld"] --> CheckNVIDIA
    CheckAMD -- No --> CheckNVIDIA
    
    CheckNVIDIA{"NVIDIA GPU present?"}
    CheckNVIDIA -- Yes --> InstallNVIDIA["Install NVIDIA Driver Stack:<br/>akmod-nvidia, akmods, kernel-devel-matched, xorg-x11-drv-nvidia-kmodsrc,<br/>xorg-x11-drv-nvidia-cuda, libva-nvidia-driver, akmod-v4l2loopback, mokutil"]
    InstallNVIDIA --> BuildModules["Force module compilation: sudo akmods --force"]
    BuildModules --> CheckOptimus{"Is Laptop Chassis AND Hybrid GPU present?"}
    CheckOptimus -- Yes --> LogOptimus["Log 'NVIDIA Optimus Hybrid Graphics detected'"] --> SecureBootGuide
    CheckOptimus -- No --> SecureBootGuide
    
    SecureBootGuide["Display Comprehensive Secure Boot & MOK Guide:<br/>1. Key generation (kmodgenca -a)<br/>2. Key import (mokutil --import public_key.der)<br/>3. Blue MOK Manager enrollment walkthrough on reboot"] --> EndDrivers
    
    CheckNVIDIA -- No --> LogNoNvidia["Log 'No NVIDIA GPU found'"] --> EndDrivers
```

---

### Step 18: Summary & Service Health Check (`show_summary`)

```mermaid
flowchart TD
    StartSummary(["Start show_summary()"]) --> CalcTime["Calculate total execution duration (minutes & seconds)"]
    CalcTime --> PrintTallies["Display summary banner:<br/>- Completed steps tally<br/>- Failed steps tally<br/>- Skipped steps tally"]
    PrintTallies --> CheckServices["Audit System Service Status:<br/>- TLP (systemctl is-active tlp)<br/>- Docker (systemctl is-active docker)<br/>- NVIDIA Driver (nvidia-smi check)<br/>- ZSH Default Shell (comparison with $SHELL)"]
    CheckServices --> VideoTestPrompt{"Verify hardware video acceleration? [y/N]"}
    
    VideoTestPrompt -- Yes --> RunVideoTests["Query FFmpeg H.264 encoders<br/>Query VA-API profiles via vainfo"] --> PrintNextSteps
    VideoTestPrompt -- No --> PrintNextSteps
    
    PrintNextSteps["Display Actionable Next Steps:<br/>1. Reboot system (applies Docker/libvirt groups & kernel drivers)<br/>2. Open new terminal (ZSH + Starship prompt)<br/>3. Review detailed log in /tmp/fedora-setup-*.log"]
    PrintNextSteps --> EndSummary(["System Ready! 🚀"])
```

---

## 4. Idempotency, State & Rollback Flowchart

How `setup.sh` handles step resumption, failure recovery, and backup restoration:

```mermaid
flowchart TD
    subgraph StateResumption ["Resumption & Interruption Lifecycle"]
        Launch["User runs ./setup.sh"] --> ReadStateFile["Read ~/.config/fedora-setup/state.txt"]
        ReadStateFile --> StepEvaluator{"For each step in active profile"}
        
        StepEvaluator --> StepInState{"Step function name<br/>present in state.txt?"}
        StepInState -- Yes (No --force) --> SkipToNext["Skip step execution<br/>(Zero redundant downloads or writes)"] --> StepEvaluator
        StepInState -- No (Or --force passed) --> PromptAndRun["Prompt user & Execute step function"]
        
        PromptAndRun --> StepSuccess{"Execution succeeded?"}
        StepSuccess -- Yes --> AppendState["Append function name to state.txt"] --> StepEvaluator
        StepSuccess -- No --> PreserveState["Do NOT write to state.txt<br/>(Step will re-prompt on next run)"] --> StepEvaluator
    end

    subgraph RollbackEngine ["Disaster Recovery & Rollback Subsystem"]
        RunRestore["User launches ./setup.sh -> Confirms 'Restore from previous backup?'"] --> ScanBackups["Find newest directory in ~/.config/fedora-setup-backups/YYYYMMDD_HHMMSS/"]
        ScanBackups --> FoundBackups{"Backup directory found?"}
        FoundBackups -- No --> LogNoBackup["Log 'No backups found' -> Exit 1"]
        FoundBackups -- Yes --> ConfirmRestore{"Restore all files from this timestamp? [y/N]"}
        
        ConfirmRestore -- Yes --> RestoreFiles["Restore original files:<br/>- ~/.zshrc<br/>- ~/.bashrc<br/>- /etc/dnf/dnf.conf<br/>- ~/.config/MangoHud/MangoHud.conf<br/>- ~/.config/starship.toml<br/>- ~/.config/kitty/kitty.conf"]
        RestoreFiles --> WipeState["Delete ~/.config/fedora-setup/state.txt<br/>(Resets state so future runs re-evaluate cleanly)"]
        WipeState --> ExitRestore(["Exit 0 (System restored to original clean state)"])
        ConfirmRestore -- No --> CancelRestore(["Cancel restore"])
    end
```
