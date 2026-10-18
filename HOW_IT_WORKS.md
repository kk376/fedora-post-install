# 🚀 How Fedora Post-Install Works: The Plain English Guide

> *"Think of a fresh Fedora install like moving into a brand-new, modern apartment. The walls are solid, the water flows, and the lights turn on—but there's no furniture, the Wi-Fi isn't optimized, the kitchen doesn't have your favorite spices, and your workbench is empty.*  
>  
> *This script is your friendly interior setup crew. It walks in with a clipboard, knocks on each room's door, asks you what you want, sets up your tools neatly, and hands you the keys with zero mess."*

---

## 📑 Table of Contents

1. [The "Before & After" Transformation](#1-the-before--after-transformation)
2. [The 4 Peace-of-Mind Safety Rules](#2-the-4-peace-of-mind-safety-rules)
3. [Choose Your Vibe: The 7 Profiles](#3-choose-your-vibe-the-7-profiles)
4. [The 17-Step Tour (Plain English Breakdown)](#4-the-17-step-tour-plain-english-breakdown)
5. [Visual Roadtrip (How the Script Flows)](#5-visual-roadtrip-how-the-script-flows)
6. [Beginner FAQ & Safety Net](#6-beginner-faq--safety-net)

---

## 1. The "Before & After" Transformation

Here is what changes on your computer when you run this setup:

```
┌───────────────────────────────┬────────────────────────────────────────────────────────┐
│ 📦 Fresh Out-of-the-Box       │ ✨ After Fedora Post-Install Setup                     │
├───────────────────────────────┼────────────────────────────────────────────────────────┤
│ 🐢 Downloads 1 package at a   │ 🚀 Downloads 10 packages in parallel from fastest      │
│    time from default servers  │    mirrors (DNF speedup + RPM Fusion + Flathub)        │
│                               │                                                        │
│ 🔇 Missing video & audio      │ 🎬 Plays all YouTube, Netflix, MP4, H.264 & H.265      │
│    codecs (legal patent limits│    videos with smooth GPU hardware acceleration        │
│                               │                                                        │
│ 🎧 Bluetooth earbuds sound    │ 🎶 Crystal-clear LDAC, AAC & SBC-XQ Hi-Fi stereo audio │
│    tinny or low quality       │    configured automatically via WirePlumber            │
│                               │                                                        │
│ ⬛ Plain black terminal       │ 🎨 Tokyo Night theme, FiraCode Nerd Font ligatures,    │
│    with basic Bash prompt     │    ZSH autosuggestions, git status & Starship prompt   │
│                               │                                                        │
│ 🎮 Steam & Discord screen-    │ 🕹️ Steam H.264 unlocked, MangoHud FPS overlay ready,   │
│    share audio broken         │    Vesktop Discord with Wayland audio sharing          │
│                               │                                                        │
│ 💻 Empty developer workspace  │ 🛠️ Compilers, Node.js, Python, PostgreSQL 18, Docker,  │
│    with no compilers or tools │    and Zed Editor with instant 1-key code runner (F5)  │
│                               │                                                        │
│ 🔒 NVIDIA Secure Boot issues  │ 🛡️ Guided MOK key enrollment walk-through so NVIDIA    │
│    causing black screens      │    drivers load flawlessly without disabling security  │
└───────────────────────────────┴────────────────────────────────────────────────────────┘
```

---

## 2. The 4 Peace-of-Mind Safety Rules

If you're nervous about running a terminal script, here are the **four ironclad safety mechanisms** built into every line of code:

### 🛡️ Rule 1: The Clipboard Rule (Zero Surprises)
The script never installs or modifies anything behind your back. Every single section stops and asks:
```
Step: Power Management
Run this step? (Y/n): 
```
If you don't want something, press `N` and it skips ahead cleanly.

### 💾 Rule 2: The Automatic Time Machine (Backups)
Before the script touches *any* configuration file on your computer (`.zshrc`, `.bashrc`, `dnf.conf`, `config.ghostty`, `kitty.conf`, `alacritty.toml`), it saves a timestamped copy into:
```
~/.config/fedora-setup-backups/
```
If you ever want to undo everything and return to how your system was before, run `./setup.sh` and answer `Y` to **"Restore from previous backup?"**.

### ⏸️ Rule 3: The Bookmark (Smart Resume)
Did your laptop battery die, did you cancel midway, or did you need to reboot for a kernel update?  
The script keeps a bookmark in `~/.config/fedora-setup/state.txt`. When you run `./setup.sh` again, it skips everything you already completed and resumes right where you left off.

### 🔒 Rule 4: No Blind Deletions (Zero Orphan Removals)
The script contains zero reckless deletion commands. Critical kernel drivers, Android tools, and virtualization packages are explicitly locked as top-level user packages so Fedora's package manager will never accidentally autoremove them.

---

## 3. Choose Your Vibe: The 6 Profiles

You don't need a heavy developer workstation if you just want to browse the web and play games. Pick the profile that matches what you do:

```
                  ┌──────────────────────────────────────────────┐
                  │    WHICH FEDORA PROFILE IS RIGHT FOR YOU?    │
                  └──────────────────────────────────────────────┘
                                         │
                 Do you want everything (workstation, dev, gaming, creator)?
                                ├── YES ──► FULL PROFILE (Default)
                                │
                                └── NO  ──► Do you want a dedicated developer workstation?
                                              ├── YES ──► DEV PROFILE (Choose dev genres)
                                              └── NO  ──► Media creator, gamer, or lean desktop?
                                                            ├── CREATOR (OBS, V4L2, GStreamer)
                                                            ├── GAMING (Steam, MangoHud, Heroic)
                                                            ├── WORKSTATION (Productivity, No gaming)
                                                            └── MINIMAL (Lean daily driver)
```

### 1. `minimal`: The Clean Minimalist (4 steps)
* **Who it's for:** People who want Fedora to feel snappy, modern, and lean, without installing heavy desktop applications.
* **What you get:** DNF download turbo, DNS, essential core CLI utilities, and modern shells (Fish/Zsh/Bash) with clean aliases.

### 2. `workstation`: The Daily Productivity Desktop (11 steps)
* **Who it's for:** Professional desktop users who want a clean, complete desktop with fonts, codecs, power policies, and GPU drivers.
* **What you get:** Everything in Minimal + Microsoft & Nerd Fonts, multimedia codecs, PipeWire dynamic sample rates, GNOME tweaks, desktop applications (Brave, Vesktop, Yazi, Flatpaks), power tuning with ZRAM, pre-driver reboot gate, and GPU drivers.

### 3. `dev`: The Software Engineer (15 steps)
* **Who it's for:** Software engineers across any discipline (`--dev-type=systems,web,android,ai,all`).
* **What you get:** Everything in Workstation + modular developer toolchains based on dev genres (systems, web, android, ai), Code Editor (Zed/Codium/Antigravity/Code), Docker & Compose, and KVM/QEMU Virtualization.

### 4. `gaming`: The Linux Gamer (12 steps)
* **Who it's for:** Gamers playing on Steam, Discord users, and media lovers.
* **What you get:** Everything in Workstation + Steam with H.264 video unlock, MangoHud FPS & temperature overlay (with scaled metrics), GameMode, and Heroic Games Launcher (Flathub Flatpak for Epic/GOG/Amazon).

### 5. `creator`: The Streamer & Content Creator (12 steps)
* **Who it's for:** People who stream, record YouTube videos, edit podcasts, or capture screens.
* **What you get:** Everything in Workstation + OBS Studio, akmod-v4l2loopback virtual camera, wf-recorder Wayland screen recorder, GStreamer media pipeline headers, and NVIDIA Broadcast AI audio noise removal.

### 6. `full`: The Complete Public Powerhouse (17 steps, Default)
* **Who it's for:** Users who want the full superset: Workstation + Dev + Gaming + Creator with all tools and toolchains.

---

## 4. The 17-Step Tour (Plain English Breakdown)

Here is a simple walkthrough of each room the setup crew visits:

---

### 📦 Step 1: DNF Supercharger & Repositories (`setup_dnf`)
* **The Problem:** Fresh Fedora downloads updates slowly (one at a time) and doesn't have access to third-party software repositories.
* **The Fix:** Configures Fedora to download 10 files at once from the fastest mirrors, enables **RPM Fusion** (the largest community repository for Fedora), and adds **Flathub** (for thousands of desktop apps).
* **Decision:** Always say **YES**.

---

### 🌐 Step 2: Private, Fast DNS (`setup_dns`)
* **The Problem:** Your internet provider's default DNS can be slow and may block or log websites you visit.
* **The Fix:** Lets you switch to **Cloudflare (1.1.1.1)**, **Google (8.8.8.8)**, or **Quad9 (9.9.9.9)** for faster, private browsing. It smartly ignores internal Docker and VM networks so you never lose connection to local development servers.
* **Decision:** Say **YES** for faster browsing. Say **NO** if you are on a university or strict corporate VPN that requires company DNS.

---

### 🛠️ Step 3: Core CLI Utilities (`setup_cli_core`)
* **The Problem:** Stock Fedora installs miss modern terminal productivity utilities (fast search, modern ls/cat, smart fuzzy finding, git clipboard).
* **The Fix:** Installs blazing-fast modern CLI essentials: `fastfetch`, `bat`, `eza`, `fd-find`, `ripgrep`, `fzf`, `zoxide`, `btop`, `duf`, `plocate`, `jq`, `wl-clipboard`, `android-tools`, and `git`.
* **Decision:** Always say **YES**.

---

### 🐚 Step 4: Shell, Starship & Modern Terminal (`setup_shell`)
* **The Problem:** The default terminal is a plain black box with basic text and standard Bash defaults.
* **The Fix:** Equips your environment with modern shells (Fish and ZSH) and optional **Starship** cross-shell prompt.
  - Interactive login shell menu (Fish [Recommended], ZSH, Bash, Skip) in `dev` and `full` profiles.
  - Interactive Starship prompt installation option with feature disclaimer in `dev` and `full` profiles.
  - Interactive developer environment menu (Git aliases, Neovim editor, Cargo/OpenCode PATH) tailored to the chosen shell in `dev` and `full` profiles.
  - Clean standard aliases (clear, ls, cat, less) across all shells without Starship or developer bloat on standard profiles (`minimal`, `workstation`, `gaming`, `creator`).
  - Modern GPU terminal emulator (Ghostty recommended, Kitty, or Alacritty) with self-contained Tokyo Night configuration.
* **Decision:** Always say **YES**.

---

### 🔤 Step 5: Beautiful Fonts & Icons (`setup_fonts`)
* **The Problem:** Microsoft Word documents look messy without standard fonts, and programmer code editors look bland without modern coding ligatures.
* **The Fix:** Installs Microsoft Core fonts (Arial, Times New Roman, Calibri), Aptos, Segoe UI, Google Noto, and downloads the gorgeous **FiraCode Nerd Font** and **Symbols Nerd Font**.
* **Decision:** Always say **YES**.

---

### 🎬 Step 6: Multimedia Codecs & Dynamic PipeWire Audio (`setup_multimedia`)
* **The Problem:** Fedora cannot ship proprietary video codecs due to legal patent restrictions, and Bluetooth headphones often suffer from low-quality audio or mic hijacking.
* **The Fix:**
  - Swaps in full **FFmpeg freeworld** codecs and GStreamer plugins so every MP4, MKV, and web video plays smoothly on your GPU.
  - Upgrades **WirePlumber Bluetooth Audio** to prioritize Hi-Fi codecs (LDAC, AAC, SBC-XQ, aptX).
  - Unlocks **PipeWire Dynamic Clock Rates** (44.1kHz up to 192kHz) for bit-perfect audio playback without lossy software resampling.
* **Decision:** Always say **YES**.

---

### 📱 Step 7: GNOME Polish & Mobile Sync (`setup_gnome`)
* **The Problem:** Out of the box, Fedora doesn't easily talk to your Android phone, and app titlebars can take up too much vertical space.
* **The Fix:**
  - Installs **GSConnect** (KDE Connect protocol) and opens firewall ports so you can sync clipboard, share files, and see phone notifications on your desktop.
  - Deploys sleek transparent titlebar styling for GTK3 and GTK4 apps.
* **Decision:** Say **YES** if you have an Android phone or love clean UI.

---

### 💻 Step 8: Desktop Applications & Productivity (`setup_desktop_apps`)
* **The Problem:** Setting up browsers, media players, and Discord with screen sharing takes manual hunting across websites.
* **The Fix:** Installs **Brave Browser**, **VLC**, **qBittorrent**, **Telegram**, **Timeshift**, **GParted**, **LocalSend** (cross-platform AirDrop alternative), **Extension Manager**, **Yazi** (Rust terminal file manager with previews), and **Vesktop** (Discord client with working Wayland screen audio).
* **Decision:** Always say **YES**.

---

### ⚡ Step 9: Power Policies & High-Performance ZRAM (`setup_power`)
* **The Problem:** Laptops drain battery quickly without proper power governors, and desktops can run out of memory during heavy compilation tasks.
* **The Fix:**
  - Hardware-aware chassis detection: skips laptop battery daemons (TLP) on desktop towers.
  - Safe AC no-sleep: disables automatic sleep when plugged into AC power while preserving battery sleep safety.
  - Applies **high-performance ZRAM memory tuning** (zstd compression algorithm with up to 16GB RAM allocation and swappiness=100) to double effective memory bandwidth.
* **Decision:** Always say **YES**.

---

### 🛠️ Step 10: Modular Development Toolchains (`setup_dev`)
* **The Problem:** Setting up compilers, Python symlinks, Node corepack (`pnpm`/`yarn`), compiler cache, and database servers manually takes hours of troubleshooting.
* **The Fix:**
  - Installs baseline developer tools (Git LFS, GPG, Neovim, GitHub/GitLab CLI).
  - **Systems Genre:** C/C++, CMake, Meson, Ninja, GDB, Valgrind, Rustup, and **ccache** (50GB compressed compiler cache).
  - **Web Genre:** Node.js, Corepack (`pnpm`/`yarn`), Python 3, and `jq`.
  - **Android Genre:** ADB/Fastboot, Java OpenJDK, Maven, Android Studio (Flatpak), and **Scrcpy** (low-latency screen mirroring).
  - **AI Genre:** Python Devel, Ruff, UV, and multi-vendor GPU compute (NVIDIA CUDA, AMD ROCm, Intel Level Zero).
  - Architecture-aware **PostgreSQL 18** server configuration.
* **Decision:** Say **YES** if you build software.

---

### 📝 Step 11: Code Editor Suite (`setup_editor`)
* **The Problem:** Installing editors, themes, font settings, and configuring code execution shortcuts is repetitive.
* **The Fix:** Lets you choose your favorite editor from a clean menu:
  1. **Zed (Recommended):** Blazing-fast GPU-accelerated editor with Catppuccin Mocha theme and a custom `zed-run` polyglot runner (F5 / Ctrl+Alt+N).
  2. 🕊️ **VS Codium:** 100% Free/Libre VS Code without Microsoft telemetry.
  3. 🚀 **Google Antigravity IDE:** The next-gen agentic developer IDE.
  4. 🔷 **VS Code:** Standard Microsoft VS Code.
* **Decision:** Pick your favorite editor!

---

### 🐳 Step 12: Docker Container Engine (`setup_docker`)
* **The Problem:** Installing Docker on Fedora often breaks container networking because Fedora's Firewall and NetworkManager interfere with Docker's virtual bridge (`docker0`).
* **The Fix:**
  - Installs Docker Engine, containerd, and Docker Compose.
  - Configures NetworkManager to leave `docker0` unmanaged.
  - Adds your user to the `docker` group (no `sudo` required).
  - Architecture-aware Docker Compose CLI plugin fallback.
* **Decision:** Say **YES** if you use containers.

---

### 🖥️ Step 13: KVM/QEMU Virtual Machines (`setup_kvm`)
* **The Problem:** Setting up hardware-accelerated Linux and Windows Virtual Machines usually requires confusing command-line configurations.
* **The Fix:**
  - Verifies CPU hardware virtualization (Intel VT-x / AMD-V).
  - Installs **Virt-Manager** and **GNOME Boxes**.
  - Modern modular libvirt socket activation (`virtqemud.socket`).
  - Windows VirtIO paravirtualized drivers.
* **Decision:** Say **YES** if you run Virtual Machines.

---

### 🎮 Step 14: Gaming Stack (`setup_gaming`)
* **The Problem:** Steam needs hardware video decoder unlocks, and gaming overlays require manual config files.
* **The Fix:**
  - Installs **Steam**, **MangoHud**, **GameMode**, and Vulkan tools.
  - Unlocks Steam H.264 video codec decoding via `steam-devices` & `mozilla-openh264`.
  - Deploys pre-tuned **MangoHud** overlay configuration (scaled metrics, alpha transparency).
  - Installs **Heroic Games Launcher** (Flathub Flatpak for Epic/GOG/Amazon games) with shared Wine prefix directory.
* **Decision:** Say **YES** if you play games.

---

### 🎥 Step 15: Creator & Streaming Suite (`setup_creator`)
* **The Problem:** Screen recording and virtual webcam routing require out-of-tree kernel modules and complex audio loopback configurations.
* **The Fix:**
  - Installs **OBS Studio**, **akmod-v4l2loopback**, and **wf-recorder** Wayland screen recorder.
  - Offers **NVIDIA Broadcast for Linux** (AI microphone noise removal and virtual green screen).
* **Decision:** Say **YES** if you create videos or stream.

---

### 🚦 Step 16: Pre-Driver Kernel Gate (`setup_pre_driver_reboot`)
* **The Problem:** If earlier package installations updated your Linux kernel, building graphics drivers (like NVIDIA akmods) right away would compile against the *old* running kernel instead of the *new* one, causing broken drivers after reboot.
* **The Fix:** Compares your running kernel against the latest installed `kernel-core`. If a newer kernel is waiting, it gracefully saves your progress and reboots first so drivers build on the exact kernel you'll be using.
* **Decision:** Say **YES** if prompted to reboot.

---

### 🎮 Step 17: Multi-Vendor GPU Drivers & Secure Boot MOK (`setup_drivers`)
* **The Problem:** NVIDIA, AMD, and Intel GPUs require completely different drivers, and NVIDIA drivers on UEFI Secure Boot systems won't load without signed keys.
* **The Fix:**
  - 🔵 **Intel GPUs:** Installs `intel-media-driver` and `libva-intel-driver` for hardware video decoding.
  - 🔴 **AMD GPUs:** Swaps in Mesa freeworld drivers for full VA-API/VDPAU video decode acceleration.
  - 🟢 **NVIDIA GPUs:** Installs `akmod-nvidia`, CUDA, and VA-API bridge, with step-by-step guidance to enroll your **MOK (Machine Owner Key)** on the blue boot screen.
  - ⚡ **Hybrid Graphics Optimization (Optimus Laptops):** Sets `VK_LOADER_DRIVERS_SELECT` to prioritize the integrated GPU so desktop apps open instantly without waking the discrete NVIDIA GPU.
* **Decision:** Always say **YES**.

---

### 🏁 Summary & Health Check (`show_summary`)
* Displays duration, profile, completed/skipped/failed step counts, active login shell, and log file path.

---

## 5. Visual Roadtrip (How the Script Flows)

```
  [ 🚀 START: ./setup.sh ]
             │
             ▼
   [ 🛡️ Preflight Checks ] ──► Internet OK? Space ≥ 20GB? Backups ready?
             │
             ▼
   [ 🎯 Select Your Profile ] ──► (minimal, workstation, dev, gaming, creator, full)
             │
             ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      THE INTERACTIVE STEP LOOP                         │
 │                                                                        │
 │   1. DNF5 Mirrors & Repos       ────► 2. Private DNS (Cloudflare)      │
 │   3. Core CLI Utilities         ────► 4. Shell, Starship & Terminal    │
 │   5. System & Nerd Fonts        ────► 6. Codecs & Dynamic PipeWire     │
 │   7. GNOME & Mobile Sync        ────► 8. Desktop Apps & Productivity   │
 │   9. Power & ZRAM Tuning        ────► 10. Modular Dev Toolchains       │
 │  11. Code Editor Suite          ────► 12. Docker & Compose Engine      │
 │  13. KVM/QEMU Virtual Machines  ────► 14. Gaming Stack & Heroic        │
 │  15. Creator Suite & OBS        ────► 16. Pre-Driver Kernel Gate       │
 │  17. GPU Drivers & Secure Boot  ───────────────────────────────────────┘
             │
             ▼
   [ 🎉 System Ready! 🚀 ] ──► Reboot once, open a new terminal, and enjoy!
```

---

## 6. Beginner FAQ & Safety Net

### Q: Will this script delete my files, pictures, or documents?
**A:** **No, never.** The script only installs software packages, configures system developer settings, and creates config files in your user profile. It never touches your personal documents, pictures, or downloads.

### Q: Can I run this on a fresh install without typing any arguments?
**A:** Yes! Just run:
```bash
chmod +x setup.sh
./setup.sh
```
It defaults to the interactive `full` profile and walks you through every choice with plain English prompts.

### Q: What if I make a mistake or want to undo a setting?
**A:** Just re-run `./setup.sh` and answer `Y` to **"Restore from previous backup?"**. It will restore your original `.zshrc`, `.bashrc`, `dnf.conf`, and other config files from timestamped backup storage.

### Q: How can I preview what the script will do without touching anything?
**A:** Run with the dry-run flag:
```bash
./setup.sh --dry-run
```
This simulates the entire installation and prints every action in purple without modifying a single byte on your disk.

---

*Made with ❤️ for the Fedora community by [Kushagra Kumar (kk376)](https://github.com/kk376).*
