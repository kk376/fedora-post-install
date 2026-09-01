# 🚀 How Fedora Post-Install Works: The Plain English Guide

> *"Think of a fresh Fedora install like moving into a brand-new, modern apartment. The walls are solid, the water flows, and the lights turn on—but there's no furniture, the Wi-Fi isn't optimized, the kitchen doesn't have your favorite spices, and your workbench is empty.*  
>  
> *This script is your friendly interior setup crew. It walks in with a clipboard, knocks on each room's door, asks you what you want, sets up your tools neatly, and hands you the keys with zero mess."*

---

## 📑 Table of Contents

1. [The "Before & After" Transformation](#1-the-before--after-transformation)
2. [The 4 Peace-of-Mind Safety Rules](#2-the-4-peace-of-mind-safety-rules)
3. [Choose Your Vibe: The 6 Profiles](#3-choose-your-vibe-the-6-profiles)
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
Before the script touches *any* configuration file on your computer (`.zshrc`, `.bashrc`, `dnf.conf`, `kitty.conf`), it saves a timestamped copy into:
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
                 Do you want a full developer & virtualization stack?
                                ├── YES ──► Are you doing media creation / streaming?
                                │             ├── YES ──► 🎬 CREATOR PROFILE
                                │             └── NO  ──► 💻 DEV or 🏢 WORKSTATION
                                │
                                └── NO  ──► Do you play games (Steam / Discord / Proton)?
                                              ├── YES ──► 🎮 GAMING PROFILE
                                              └── NO  ──► 🪶 MINIMAL PROFILE
```

### 🪶 1. `minimal` — The Clean Minimalist
* **Who it's for:** People who want Fedora to feel snappy, modern, and play videos, without installing heavy dev stacks.
* **What you get:** DNF download turbo, DNS, modern fonts, Starship terminal, Brave browser, multimedia codecs, and GPU drivers.

### 💻 2. `dev` — The Software Engineer
* **Who it's for:** Web developers, backend programmers, and DevOps engineers.
* **What you get:** Everything in Minimal + Power management, No-Sleep lock, GNOME tools, compilers (GCC/Clang/Rust/Node/Python), PostgreSQL 18, Zed Editor / Codium, Docker Engine, and KVM Virtual Machines.

### 🎮 3. `gaming` — The Linux Gamer
* **Who it's for:** Gamers playing on Steam, Discord users, and media lovers.
* **What you get:** Everything in Minimal + Power tuning, GNOME tools, Steam with H.264 video unlock, MangoHud FPS & temperature overlay, Vesktop (Discord with screen audio), and Flatpaks.

### 🏢 4. `workstation` — The Daily Driver
* **Who it's for:** A balanced power-user workstation for general productivity, virtualization, and casual gaming.
* **What you get:** Gaming stack + Essential utilities + KVM/QEMU virtual machines + Full desktop polish.

### 🎬 5. `creator` — The Streamer & Content Creator
* **Who it's for:** People who stream, record YouTube videos, edit podcasts, or design GTK apps.
* **What you get:** Gaming stack + OBS Studio, V4L2 virtual camera loopback, GStreamer media pipeline headers, GTK4/Adwaita design tools, and NVIDIA Broadcast AI audio noise removal.

### 🚀 6. `full` — The Complete Powerhouse *(Default)*
* **Who it's for:** Users who want everything configured at once, including third-party COPR packages (Scrcpy Android mirroring, Yazi file manager) and Debian package tools.

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
* **The Fix:** Lets you switch to **Cloudflare (1.1.1.1)** or **Google (8.8.8.8)** for faster browsing. It smartly ignores internal Docker and VM networks so you never lose connection to local development servers.
* **Decision:** Say **YES** for faster browsing. Say **NO** if you are on a university or strict corporate VPN that requires company DNS.

---

### ⚡ Step 3: Battery & Power Management (`setup_power`)
* **The Problem:** Laptops can run hot or drain battery quickly without proper power governors.
* **The Fix:** Offers to install **TLP** for advanced battery savings. It transparently explains the difference between TLP and Fedora's built-in power profiles so you can choose what's best for your machine.
* **Decision:** Say **YES** on Intel/older laptops for max battery. Say **NO** on modern AMD Ryzen laptops to keep GNOME's built-in Power Slider.

---

### ☕ Step 4: No-Sleep Mode (`setup_nosleep`)
* **The Problem:** Fedora loves to put your computer or login lockscreen to sleep while you are downloading large files, compiling code, or stepping away for a coffee.
* **The Fix:** Disables automatic sleep when plugged into AC power for both your user account and the GDM login screen.
* **Decision:** Say **YES** if you hate your PC going to sleep during long tasks.

---

### 🔤 Step 5: Beautiful Fonts & Icons (`setup_fonts`)
* **The Problem:** Microsoft Word documents look messy without standard fonts, and programmer code editors look bland without modern coding ligatures.
* **The Fix:** Installs Microsoft Core fonts (Arial, Times New Roman, Calibri), Google Noto, and downloads the gorgeous **FiraCode Nerd Font** (which renders arrows `->` as `→` and adds terminal icons).
* **Decision:** Always say **YES**.

---

### 🐚 Step 6: Dream Terminal & Shell (`setup_shell`)
* **The Problem:** The default terminal is a plain black box with basic text.
* **The Fix:** Upgrades your terminal to **ZSH** with the **Starship** prompt. You get:
  - 🔮 Ghost suggestions (press Right Arrow to auto-complete commands).
  - 🎨 Syntax highlighting (green for valid commands, red for typos).
  - 🌿 Git branch badges and execution timer ("took 1.2s").
  - 🐱 Optional **Kitty Terminal** with Tokyo Night dark theme and blurred transparency.
  - ⚡ Optional **KKFetch** (ultra-fast Rust system info banner created by Kushagra Kumar).
* **Decision:** Always say **YES**.

---

### 🎬 Step 7: Brave Browser & Media Codecs (`setup_browser_multimedia`)
* **The Problem:** Fedora cannot ship proprietary video codecs due to legal patent restrictions. YouTube videos can drop frames, and Bluetooth headphones often sound tinny.
* **The Fix:**
  - Installs **Brave Browser** (blocks ads and trackers by default).
  - Swaps in full **FFmpeg freeworld** codecs so every MP4, MKV, and web video plays smoothly on your GPU.
  - Upgrades **WirePlumber Bluetooth Audio** to prioritize Hi-Fi codecs (LDAC, AAC, SBC-XQ).
* **Decision:** Always say **YES**.

---

### 📦 Step 8: Curated COPR Utilities (`setup_copr`)
* **The Problem:** Some amazing tools aren't in standard Fedora repositories yet.
* **The Fix:** Confined strictly to the `full` profile, this step asks if you want:
  - 📱 **Scrcpy:** Plug in your Android phone via USB and control it with your mouse and keyboard with ultra-low latency.
  - 📂 **Yazi:** A terminal file manager in Rust with instant inline image and PDF previews.
* **Decision:** Say **YES** to what you need; say **NO** to skip.

---

### 📱 Step 9: GNOME Polish & Mobile Sync (`setup_gnome`)
* **The Problem:** Out of the box, Fedora doesn't easily talk to your Android phone, and app titlebars can take up too much vertical space.
* **The Fix:**
  - Installs **GSConnect** (KDE Connect protocol) and opens firewall ports so you can sync clipboard, share files, and see phone notifications on your desktop.
  - Deploys sleek transparent titlebar styling for GTK3 and GTK4 apps.
* **Decision:** Say **YES** if you have an Android phone or love clean UI.

---

### 🧰 Step 10: Essential Toolbox & Gaming (`setup_packages`)
* **The Problem:** Missing day-to-day tools like Fastfetch, Timeshift (system restore), VLC, Neovim, ADB/Fastboot, or Steam gaming optimizations.
* **The Fix:** Installs a comprehensive toolset, unlocks Steam's hardware H.264 video decoder, creates a gaming FPS HUD overlay (**MangoHud**), and offers **Vesktop** (Discord with working Wayland screen audio) and **Stirling-PDF** (offline PDF Swiss Army knife).
* **Decision:** Always say **YES**.

---

### 💻 Step 11: Developer Engine & PostgreSQL 18 (`setup_dev`)
* **The Problem:** Setting up compilers, Python symlinks, Node corepack (`pnpm`/`yarn`), compiler cache, and database servers manually takes hours of troubleshooting.
* **The Fix:**
  - Installs GCC, Clang, Make, CMake, and optional full **Rust toolchain**.
  - Configures **50GB compressed compiler caching (`ccache`)** so re-compiling C/C++/Rust code takes seconds instead of minutes.
  - Installs official **PostgreSQL 18 Server** from PGDG, initializes the database automatically, enables the service, and installs **pgAdmin 4** Desktop.
* **Decision:** Say **YES** if you build software or websites.

---

### 📝 Step 12: Code Editor Suite & Polyglot Runner (`setup_editor`)
* **The Problem:** Installing editors, themes, font settings, and configuring code execution shortcuts is repetitive.
* **The Fix:** Lets you choose your favorite editor from a clean menu:
  1. ⚡ **Zed (Recommended):** Blazing-fast GPU-accelerated editor with Catppuccin Mocha theme and a custom `zed-run` engine—press **F5** or **Ctrl+Alt+N** to run Python, Rust, C, C++, Go, JS, or Bash instantly. If you press **Ctrl+C**, it drops you into an interactive shell instead of quitting!
  2. 🕊️ **VS Codium:** 100% Free/Libre VS Code without Microsoft telemetry or proprietary branding.
  3. 🚀 **Google Antigravity IDE:** The next-gen agentic developer IDE.
  4. 🔷 **VS Code:** Standard Microsoft VS Code.
* **Decision:** Pick your favorite editor!

---

### 📦 Step 13: Sandboxed Flatpak Apps (`setup_flatpaks`)
* **The Problem:** Need reliable utilities without polluting system libraries.
* **The Fix:** Installs **LocalSend** (cross-platform AirDrop alternative for local Wi-Fi sharing), **Mission Center** (modern Windows-like Task Manager), and **ProtonPlus** (manage custom Proton-GE gaming engines).
* **Decision:** Say **YES**.

---

### 🐳 Step 14: Docker Container Engine (`setup_docker`)
* **The Problem:** Installing Docker on Fedora often breaks container networking because Fedora's Firewall and NetworkManager interfere with Docker's virtual bridge (`docker0`).
* **The Fix:**
  - Installs Docker Engine and containerd.
  - Configures NetworkManager and Firewalld to leave `docker0` alone so container networking never breaks.
  - Adds your user to the `docker` group (no more typing `sudo docker`).
  - Downloads **Docker Compose v2** CLI plugin.
* **Decision:** Say **YES** if you use containers.

---

### 🖥️ Step 15: KVM/QEMU Virtual Machines (`setup_kvm`)
* **The Problem:** Setting up hardware-accelerated Linux and Windows Virtual Machines usually requires confusing command-line configurations.
* **The Fix:**
  - Verifies your CPU has hardware virtualization enabled in BIOS (Intel VT-x / AMD-V).
  - Installs **Virt-Manager** and **GNOME Boxes**.
  - Switches to modern on-demand socket activation (`virtqemud.socket`).
  - Installs official **Windows VirtIO high-speed disk & network drivers**.
  - Tunes kernel memory latency with the `virtual-host` performance profile.
* **Decision:** Say **YES** if you run Virtual Machines.

---

### 🚦 Step 16: Pre-Driver Kernel Gate (`setup_pre_driver_reboot`)
* **The Problem:** If Step 1 updated your Linux kernel, building graphics drivers (like NVIDIA) right away would compile against the *old* kernel instead of the *new* one, causing broken drivers after reboot.
* **The Fix:** Checks if your running kernel matches the newest installed kernel. If a newer kernel is waiting, it gracefully saves your progress and asks to reboot first so drivers build on the exact kernel you'll be using.
* **Decision:** Say **YES** if prompted to reboot.

---

### 🎮 Step 17: Smart GPU Drivers & Secure Boot MOK (`setup_drivers`)
* **The Problem:** NVIDIA, AMD, and Intel GPUs require completely different drivers, and NVIDIA drivers on UEFI Secure Boot systems won't load without signed keys.
* **The Fix:**
  - 🔵 **Intel GPUs:** Installs `intel-media-driver` for hardware video decoding.
  - 🔴 **AMD GPUs:** Swaps in Mesa freeworld drivers for full video decode acceleration.
  - 🟢 **NVIDIA GPUs:** Installs `akmod-nvidia`, CUDA, virtual camera modules, and provides an idiot-proof step-by-step walkthrough to enroll your **MOK (Machine Owner Key)** on the blue boot screen so Secure Boot stays 100% enabled.
* **Decision:** Always say **YES**.

---

### 🏁 Step 18: Summary & Health Check (`show_summary`)
* **The Problem:** You finish running a script and wonder: *"Did everything actually work?"*
* **The Fix:** Displays a clean scorecard:
  - ⏱️ Total time taken and step counts (Completed / Skipped / Failed).
  - 🩺 Live service health audit (TLP, Docker, NVIDIA, Default Shell).
  - 📺 Optional hardware video acceleration test (`vainfo`).
  - 🚀 Actionable next steps so you know exactly what to do next.

---

## 5. Visual Roadtrip (How the Script Flows)

```
  [ 🚀 START: ./setup.sh ]
             │
             ▼
   [ 🛡️ Preflight Checks ] ──► Internet OK? Space ≥ 20GB? Backups ready?
             │
             ▼
   [ 🎯 Select Your Profile ] ──► (minimal, dev, gaming, workstation, creator, full)
             │
             ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      THE INTERACTIVE STEP LOOP                         │
 │                                                                        │
 │   1. DNF Fast Mirrors & Repos   ────► 2. Private DNS (Cloudflare)     │
 │   3. Battery / Power Tuning     ────► 4. No-Sleep AC Policy           │
 │   5. System & Nerd Fonts        ────► 6. ZSH + Starship Terminal      │
 │   7. Brave & Video Codecs       ────► 8. Curated COPR Tools           │
 │   9. GNOME & Android Sync       ────► 10. Essential Packages & Gaming │
 │  11. Dev Stack & PostgreSQL 18  ────► 12. Code Editor (Zed / Codium)  │
 │  13. Flatpak Desktop Apps       ────► 14. Docker Container Engine     │
 │  15. KVM/QEMU Virtual Machines  ────► 16. Kernel Reboot Gate          │
 │  17. Smart GPU Drivers & MOK    ───────────────────────────────────────┘
             │
             ▼
   [ 🩺 System Health Audit ] ──► TLP: Active | Docker: Active | NVIDIA: Ready
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
