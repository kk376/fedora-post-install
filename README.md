# Fedora Post-Install Setup Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An interactive, hardware-aware post-installation script for Fedora Workstation (GNOME).

Built from years of actual Fedora usage, covering the things I find myself setting up on every fresh install: driver detection, multimedia codecs, dev tools, gaming, shell customization, Docker, and virtualization.

> [!NOTE]
> **Architecture Support:** This script is engineered with architecture-aware detection supporting **x86_64** and **aarch64** architectures across **AMD, Intel, and NVIDIA** hardware, with vendor-specific GPU driver compilation and GPU compute runtimes (CUDA / ROCm / Level Zero).

---

## Features

- **Interactive**: every step asks before running; nothing happens behind your back
- **Hardware-aware**: detects Intel / AMD / NVIDIA GPUs, hybrid Optimus setups, chassis type (laptop vs desktop), and CPU virtualization support
- **Secure Boot-aware NVIDIA setup**: builds kernel modules, generates keys, and walks you through MOK enrollment
- **Idempotent**: state file tracks what's done; you can interrupt and pick up where you left off, or `--force` to re-run
- **Profile-based**: six profiles with layered modular architecture so you only install what you actually need
- **Dry-run mode**: preview everything without touching the system
- **Backup and restore**: backs up config files before modifying them
- **Technical guide**: see [HOW_IT_WORKS.md](HOW_IT_WORKS.md) for execution lifecycle, profile hierarchy, and security details

---

## What's New in v9.0.0

- **Modular Architecture & Self-Bootstrapper**: Decomposed into 23 cohesive source modules under `src/` driven by a clean 43-line self-bootstrapping runner with zero duplicate git bloat.
- **Interactive 4-Tier Debloat Engine (`setup_debloat`)**: Interactively suppresses unnecessary background daemons (`rygel`, `cups-browsed`, `ModemManager`), removes desktop clutter and heavy office suites, reclaims 200–400MB idle RAM (`gnome-software`/`PackageKit`), and prevents DNF weak dependency creep.
- **Encrypted DNS-over-TLS (DoT)**: System-wide encrypted DNS resolution via `systemd-resolved` drop-ins with SNI hostname verification across Cloudflare, Quad9, and Google.
- **Fedora 45 Modernization**: Integrated GNOME Adwaita typography (`adwaita-sans-fonts`, `adwaita-mono-fonts`), variable Noto fonts, and COLRv1 color emoji.
- **Mesa Vulkan Video & NVIDIA Power Daemons**: Added `mesa-vulkan-drivers-freeworld` swap for hardware Vulkan Video acceleration, and enabled `nvidia-suspend`/`hibernate`/`resume` units for rock-solid power management.
- **D3cold Hybrid GPU Sleep**: Full 4-variable environment profile enabling discrete NVIDIA GPUs to enter true low-power sleep on laptops.
- **Native Fedora PostgreSQL**: Switched from brittle external PGDG yum repositories to official native Fedora packages.

See [CHANGELOG.md](CHANGELOG.md) for the full history.

---

## Usage

### Quick Start (One-Liner)

Run directly via `curl` without cloning the repository:

```bash
# Full profile, interactive
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kk376/fedora-post-install/main/setup.sh)"

# Preview dev profile without making changes
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kk376/fedora-post-install/main/setup.sh)" -- --profile=dev -n
```

### Local Clone

```bash
# Clone repository
git clone https://github.com/kk376/fedora-post-install.git
cd fedora-post-install

# Full profile, interactive
./setup.sh

# Preview without changes
./setup.sh --dry-run

# Re-run already-completed steps
./setup.sh --force
```

When run interactively without options, `./setup.sh` displays a menu to select your desired profile directly from the terminal:
1. `minimal` (4 steps)
2. `workstation` (12 steps: default)
3. `dev` (16 steps: includes prompt for developer genres: systems, web, android, ai, or all)
4. `gaming` (13 steps)
5. `creator` (13 steps)
6. `full` (18 steps)

### Profiles

| Profile       | Steps | What it installs                                                                                             |
| ------------- | :---: | ------------------------------------------------------------------------------------------------------------ |
| `minimal`     | 4     | DNF config, DNS, core CLI utilities, shell (Fish/Zsh/Bash) & terminal                                        |
| `workstation` | 12    | Minimal + fonts, codecs & dynamic PipeWire audio, GNOME tweaks, debloat, desktop apps, power, GPU drivers    |
| `dev`         | 16    | Workstation + developer toolchains (`--dev-type`), Code Editor, Docker & Compose, KVM/QEMU, GPU drivers (last)|
| `gaming`      | 13    | Workstation + Steam (H.264 unlock), MangoHud, GameMode, Heroic Games Launcher, GPU drivers (last)            |
| `creator`     | 13    | Workstation + OBS Studio, v4l2loopback, wf-recorder, NVIDIA Broadcast, GPU drivers (last)                    |
| `full`        | 18    | Complete power-user suite: Workstation + Dev + Gaming + Creator + GPU drivers                                |

---

## Requirements

- **Architecture:** `x86_64` or `aarch64` (AMD, Intel, NVIDIA).
- **OS:** Fedora 44 Workstation
- **Desktop:** GNOME
- **Disk:** At least 20GB free (varies by profile)
- **Tested on:** Intel, AMD, and NVIDIA systems, both desktop and laptop

---

## Warnings

- Some steps require a reboot (GPU drivers, Docker group, Secure Boot, KVM)
- NVIDIA users: read the Secure Boot prompts carefully; follow the MOK enrollment steps when prompted and complete key enrollment on reboot
- Default shell change (interactive choice for Fish, ZSH, or Bash in Dev and Full profiles) requires a logout/login
- The VSCodium repository is imported with official GPG key verification (`https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg`).

---

## What Gets Installed

### Core

DNF optimization (parallel downloads, fastest mirror, version pinning), RPM Fusion, Flathub, optional DNS override (Cloudflare or Google), disable auto-sleep (GDM system dconf keyfile + user session), system fonts and FiraCode Nerd Font.

### Shell

Fish (recommended default) and ZSH, syntax highlighting, autosuggestions, clean modern aliases (clear, ls, cat, less). Developer and full profiles feature interactive login shell selection (Fish, ZSH, Bash), an interactive prompt for Starship cross-shell prompt installation with feature disclaimer, and a dedicated menu for developer environment exports and Git aliases. All other profiles receive clean standard aliases without Starship or developer environment exports. Developer and full profiles also include interactive modern GPU terminal selection (Ghostty recommended, Kitty, or Alacritty) with self-contained Tokyo Night configuration.

### Power

TLP (optional, warns about GNOME power profiles conflict), tuned virtual-host profile for KVM.

### Multimedia & Browsers

Brave Browser, FFmpeg freeworld, VA-API / NVENC support, OpenH264.

### GPU Drivers

Intel media driver, AMD freeworld VA/VDPAU, NVIDIA proprietary (akmods, Secure Boot key enrollment with guided walkthrough).

### Dev Tools

GCC, Clang, LLVM, ccache (interactive disclaimer prompt for 10GB compressed cache in systems genre), Java, Node.js, Python, Ruff linter/formatter, PostgreSQL 18, Docker + Docker Compose, Corepack, Code Editor selection (Zed, VS Codium, Antigravity IDE, or VS Code), Rust (optional), Git LFS & git-filter-repo, Android tools, debuggers, build systems.

### Gaming

Steam (with H.264 unlock), MangoHud (auto-configured with 32px HUD scaling, alpha transparency, and rounded corners), Vesktop, and Heroic Games Launcher (official Flathub Flatpak for Epic/GOG/sideloaded games, pre-configured with `disableUMU` to eliminate container exit lag, shared wine prefixes, and NVIDIA Prime offload). Included on `gaming` and `full` profiles.

### Virtualization

KVM/QEMU, libvirt with socket activation, virt-manager, VirtIO drivers for Windows VMs, firewall and storage pool setup.

### GNOME

GNOME Tweaks, Extension Manager, extension recommendations.

---

## Development & Testing

Modular source files live under `src/`. The root `setup.sh` is a lean 45-line entrypoint that sources `src/` modules when cloned locally, or self-bootstraps via GitHub archive when executed remotely over `curl`:

```bash
# Run ShellCheck across all scripts
make lint

# Run all 7 automated test suites
make test

# Assemble standalone distribution bundle in dist/ (optional)
make build

# Or run complete validation pipeline (lint + test)
make check
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

## Technical Architecture & Guide

Want to know exactly what this script does before running it?
- 📖 **[HOW_IT_WORKS.md](HOW_IT_WORKS.md)**: Technical architecture guide covering process execution, profile layering, state tracking, and disaster recovery.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines and testing instructions.

## License

MIT. See [LICENSE](LICENSE).
