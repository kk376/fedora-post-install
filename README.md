# Fedora 44 Post-Install Setup Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An interactive post-installation script for Fedora 44 Workstation (GNOME).

Built from years of actual Fedora usage, covering the things I find myself setting up on every fresh install: driver detection, multimedia codecs, dev tools, gaming, shell customization, Docker, and virtualization.

> [!WARNING]
> **Hardware Architecture Requirement:** This script is exclusively engineered for **x86_64** architecture systems with **AMD, Intel, and NVIDIA** hardware. ARM-based platforms, including **Qualcomm Snapdragon X Elite / X Plus** laptops, are **not supported**. Core components (Steam, NVIDIA akmods, x86_64 third-party RPMs, x86 KVM virtualization, and x86 power governors) will fail or cause system conflicts on ARM64.

---

## Features

- **Interactive**: every step asks before running; nothing happens behind your back
- **Hardware-aware**: detects Intel / AMD / NVIDIA GPUs, hybrid Optimus setups, and CPU virtualization support
- **Secure Boot-aware NVIDIA setup**: builds kernel modules, generates keys, and walks you through MOK enrollment
- **Idempotent**: state file tracks what's done; you can interrupt and pick up where you left off, or `--force` to re-run
- **Profile-based**: seven profiles so you only install what you actually need
- **Dry-run mode**: preview everything without touching the system
- **Backup and restore**: backs up config files before modifying them
- **Plain English guide**: see [HOW_IT_WORKS.md](HOW_IT_WORKS.md) for a friendly, creative layman walkthrough and transformation guide
- **Visual architecture**: see [PSEUDOCODE.md](PSEUDOCODE.md) for end-to-end Mermaid flowcharts and step-by-step logic specs

---

## What's New in v5.8.0

- **Profile-Gated Default Shell Selection:** Interactive login shell menu (Fish [Recommended], ZSH, Bash, Skip) in developer and full profiles, with automated Fish configuration and developer exports for the personal profile.
- **Interactive Developer Environment Menu:** Interactive menu in developer and full profiles to choose between full developer environment exports and Git aliases vs clean standard aliases.
- **Profile-Gated Starship Cross-Shell Prompt:** Interactive prompt with technical disclaimer explaining performance and git features in developer and full profiles; automated deployment in the personal profile; completely bypassed in minimal, workstation, gaming, and creator profiles.
- **Interactive ccache Compiler Cache:** Gated to the systems developer genre across developer, full, and personal profiles with an informative technical disclaimer explaining C and C++ compilation caching benefits.
- **GPU Terminal Emulator Selector:** Interactive selection in developer and full profiles for modern GPU-accelerated terminal emulators (Ghostty recommended as default, Kitty, or Alacritty) with automated deployment of Tokyo Night configurations synced from `dev-suite`.
- **Personal Profile Ghostty Automation:** Automated installation of Ghostty via Copr and deployment of author configs and GTK styling from `dev-suite` without interactive prompts.
- **Heroic Games Launcher Flathub Migration:** Migrated Heroic Games Launcher from DNF RPM to the official Flathub Flatpak (`com.heroicgameslauncher.hgl`) as recommended by upstream maintainers, with automated sandbox configuration and shared Wine prefix initialization.
- **Stock Terminal Preservation:** Decoupled Kitty terminal emulator from unconditional setup, ensuring minimal, workstation, gaming, and creator profiles retain stock Fedora Ptyxis cleanly.

See [CHANGELOG.md](CHANGELOG.md) for the full history.

---

## Usage

```bash
# Full profile, interactive
./setup.sh

# Preview without changes
./setup.sh --dry-run

# Re-run already-completed steps
./setup.sh --force
```

When run interactively without options, `./setup.sh` displays a menu to select your desired profile directly from the terminal:
1. `minimal` (7 steps)
2. `workstation` (11 steps)
3. `gaming` (11 steps)
4. `creator` (11 steps)
5. `dev` (16 steps: includes prompt for developer genres: systems, web, android, ai, or all)
6. `full` (17 steps: default)
7. `personal` (17 steps)

### Profiles

| Profile       | Steps | What it installs                                                                                             |
| ------------- | :---: | ------------------------------------------------------------------------------------------------------------ |
| `minimal`     | 7     | DNF config, DNS, fonts, shell (Fish/Zsh), Brave & codecs, GPU drivers (last)                     |
| `workstation` | 11    | Minimal + power, GNOME tools & AppIndicator, productivity packages, Flatpaks (Extension Manager), GPU drivers (last) |
| `gaming`      | 11    | Minimal + power, GNOME tools, gaming packages (Steam, MangoHud, GameMode, Vesktop, Heroic Games Launcher), Flatpaks, GPU drivers (last) |
| `creator`     | 11    | Minimal + power, GNOME tools, creator tools (OBS, akmod-v4l2loopback, GStreamer, NV Broadcast), Flatpaks, GPU drivers (last) |
| `dev`         | 16    | Minimal + power, no-sleep, GNOME tools, dev genre packages (`--dev-type`), Code Editor, Flatpaks (Android Studio), Docker, KVM/QEMU, GPU drivers (last) |
| `full`        | 17    | Complete public power-user superset: workstation + dev + gaming + creator, COPR packages                     |
| `personal`    | 17    | Author's bespoke workflow: Full + ONLYOFFICE (LibreOffice swap), Ghostty with dev-suite configs, automated Fish & Starship, PostgreSQL 18, dpkg-dev, kkfetch, cliamp, ani-cli |

---

## Requirements

- **Architecture:** `x86_64` (AMD, Intel, NVIDIA). ARM64 / Snapdragon platforms are not supported.
- **OS:** Fedora 44 Workstation
- **Desktop:** GNOME
- **Disk:** At least 20GB free (varies by profile)
- **Tested on:** Intel, AMD, and NVIDIA systems, both desktop and laptop

---

## Warnings

- Some steps require a reboot (GPU drivers, Docker group, Secure Boot, KVM)
- NVIDIA users: read the Secure Boot prompts carefully; follow the MOK enrollment steps when prompted and complete key enrollment on reboot
- Default shell change (interactive choice for Fish, ZSH, or Bash in Dev and Full profiles; automatically Fish in Personal profile) requires a logout/login
- The VSCodium repository is imported with official GPG key verification (`https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg`).

---

## What Gets Installed

### Core

DNF optimization (parallel downloads, fastest mirror, version pinning), RPM Fusion, Flathub, optional DNS override (Cloudflare or Google), disable auto-sleep (GDM system dconf keyfile + user session), system fonts and FiraCode Nerd Font.

### Shell

Fish (recommended default) and ZSH, syntax highlighting, autosuggestions, clean modern aliases (clear, ls, cat, less). Developer and full profiles feature interactive login shell selection (Fish, ZSH, Bash), an interactive prompt for Starship cross-shell prompt installation with feature disclaimer, and a dedicated menu for developer environment exports and Git aliases. The personal profile automatically configures Fish as the default shell and deploys Starship with all developer exports directly enabled. All other profiles receive clean standard aliases without Starship or developer environment exports. Developer and full profiles also include interactive modern GPU terminal selection (Ghostty recommended, Kitty, or Alacritty) with Tokyo Night configuration synced from dev-suite, while the personal profile deploys Ghostty automatically.

### Power

TLP (optional, warns about GNOME power profiles conflict), tuned virtual-host profile for KVM.

### Multimedia & Browsers

Brave Browser, FFmpeg freeworld, VA-API / NVENC support, OpenH264.

### GPU Drivers

Intel media driver, AMD freeworld VA/VDPAU, NVIDIA proprietary (akmods, Secure Boot key enrollment with guided walkthrough).

### Dev Tools

GCC, Clang, LLVM, ccache (interactive disclaimer prompt for 50GB compressed cache in systems genre), Java, Node.js, Python, Ruff linter/formatter, PostgreSQL 18, Docker + Docker Compose, Corepack, Code Editor selection (Zed, VS Codium, Antigravity IDE, or VS Code), Rust (optional), Git LFS & git-filter-repo, Android tools, debuggers, build systems.

### Gaming

Steam (with H.264 unlock), MangoHud (auto-configured with 32px HUD scaling, alpha transparency, and rounded corners), Vesktop, and Heroic Games Launcher (official Flathub Flatpak for Epic/GOG/sideloaded games, pre-configured with `disableUMU` to eliminate container exit lag, shared wine prefixes, and NVIDIA Prime offload). Included on `gaming`, `full`, and `personal` profiles.

### Virtualization

KVM/QEMU, libvirt with socket activation, virt-manager, VirtIO drivers for Windows VMs, firewall and storage pool setup.

### GNOME

GNOME Tweaks, Extension Manager, extension recommendations.

---

## Testing

The repository includes automated test suites covering all profiles, CLI arguments, helper functions, and backup/restore workflows:

```bash
# Run all test suites
bash tests/run_tests.sh
```

---

## Troubleshooting

**Script failed mid-run?**
Re-run it. The state file tracks progress, so it picks up from the last successful step.

**Low disk space warning?**
Free up space or acknowledge the prompt to continue anyway.

**Docker not working after install?**
Reboot to apply group membership, then test:
```bash
docker run --rm hello-world
```

**KVM permission denied?**
Run the post-reboot commands the script shows you, or:
```bash
sudo usermod -aG libvirt $USER
# Then reboot
```

**NVIDIA drivers not loading?**
Complete MOK enrollment on reboot (the blue "MOK Manager" screen).

**Bluetooth earbuds/headset sound degraded or tinny?**
When an application (Chrome, Discord, OBS) accesses the microphone, PipeWire switches Bluetooth devices from **A2DP Stereo (AAC / SBC-XQ)** to **HFP/HSP Handsfree (16kHz mono)**.
*Fix:* Open **GNOME Settings ➔ Sound**, set **Input Device** to your laptop's **Internal Microphone** (not the Bluetooth headset), then disconnect and reconnect Bluetooth.

**Chrome / Chromium video playback showing vertical split line on YouTube?**
On Linux/Wayland with hybrid AMD/Mesa graphics, Chromium's hardware video decoder can render a 1px seam across viewport tiles.
*Fix:* In Google Chrome, go to `chrome://settings/system` ➔ Toggle **"Use graphics acceleration when available"** to **OFF** ➔ Relaunch. (Ryzen/Intel multi-core CPU handles 4K/1080p software decode with <3% CPU).

---

## Getting Started

```bash
git clone https://github.com/kk376/fedora-post-install.git
cd fedora-post-install
chmod +x setup.sh
./setup.sh
```

## How It Works & Architecture Guides

Want to know exactly what this script does before running it?
- 📖 **[HOW_IT_WORKS.md](HOW_IT_WORKS.md)**: A friendly, creative, plain-English guide covering the "Before vs After" transformation, peace-of-mind safety rules, profile picker, and beginner FAQ.
- 🗺️ **[PSEUDOCODE.md](PSEUDOCODE.md)**: Detailed visual Mermaid flowcharts, decision trees, and step-by-step logic specs for all 18 functions and disaster recovery mechanisms.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines and testing instructions.

## License

MIT. See [LICENSE](LICENSE).
