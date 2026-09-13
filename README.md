# Fedora 44 Post-Install Setup Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An interactive post-installation script for Fedora 44 Workstation (GNOME).

Built from years of actual Fedora usage, covering the things I find myself setting up on every fresh install: driver detection, multimedia codecs, dev tools, gaming, shell customization, Docker, and virtualization.

---

## Features

- **Interactive**: every step asks before running; nothing happens behind your back
- **Hardware-aware**: detects Intel / AMD / NVIDIA GPUs, hybrid Optimus setups, and CPU virtualization support
- **Secure Boot-aware NVIDIA setup**: builds kernel modules, generates keys, and walks you through MOK enrollment
- **Idempotent**: state file tracks what's done; you can interrupt and pick up where you left off, or `--force` to re-run
- **Profile-based**: six profiles so you only install what you actually need
- **Dry-run mode**: preview everything without touching the system
- **Backup and restore**: backs up config files before modifying them
- **Plain English guide**: see [HOW_IT_WORKS.md](HOW_IT_WORKS.md) for a friendly, creative layman walkthrough and transformation guide
- **Visual architecture**: see [PSEUDOCODE.md](PSEUDOCODE.md) for end-to-end Mermaid flowcharts and step-by-step logic specs

---

## What's New in v5.5.8

- **Complete Microsoft Office Font Interoperability:** Automatically installs modern **Aptos** (Microsoft 365 default body typeface across Word, Excel, PowerPoint, and Outlook), extracts genuine **Cambria Regular** (`cambria.ttc`, including Cambria Math) from official Microsoft cabinet archives, and installs the **Segoe UI** font family into `~/.local/share/fonts/ms-fonts/`.
- **Metric-Compatible Font Fallbacks:** Added `google-crosextra-caladea-fonts` alongside `google-carlito-fonts` in system DNF packages for native metric-compatible Cambria and Calibri substitution in LibreOffice.
- **Process Monitoring:** Replaced `htop` with modern `btop` across essential utilities.

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
5. `dev` (16 steps — includes prompt for developer genres: systems, web, android, ai, or all)
6. `full` (17 steps — default)
7. `personal` (17 steps)

### Profiles

| Profile       | Steps | What it installs                                                                                             |
| ------------- | :---: | ------------------------------------------------------------------------------------------------------------ |
| `minimal`     | 7     | DNF config, DNS, fonts, shell (Fish/Zsh + Starship), Brave & codecs, GPU drivers (last)                     |
| `workstation` | 11    | Minimal + power, GNOME tools & AppIndicator, productivity packages, Flatpaks (Extension Manager), GPU drivers (last) |
| `gaming`      | 11    | Minimal + power, GNOME tools, gaming packages (Steam, MangoHud, GameMode, Vesktop, Heroic Games Launcher), Flatpaks, GPU drivers (last) |
| `creator`     | 11    | Minimal + power, GNOME tools, creator tools (OBS, akmod-v4l2loopback, GStreamer, NV Broadcast), Flatpaks, GPU drivers (last) |
| `dev`         | 16    | Minimal + power, no-sleep, GNOME tools, dev genre packages (`--dev-type`), Code Editor, Flatpaks (Android Studio), Docker, KVM/QEMU, GPU drivers (last) |
| `full`        | 17    | Complete public power-user superset: workstation + dev + gaming + creator, COPR packages                     |
| `personal`    | 17    | Author's bespoke workflow: Full + PostgreSQL 18 service, pgAdmin 4, 50GB ccache, dpkg-dev, X11 dev headers, kkfetch |

---

## Requirements

- **OS:** Fedora 44 Workstation
- **Desktop:** GNOME
- **Disk:** At least 20GB free (varies by profile)
- **Tested on:** Intel, AMD, and NVIDIA systems, both desktop and laptop

---

## Warnings

- Some steps require a reboot (GPU drivers, Docker group, Secure Boot, KVM)
- NVIDIA users: read the Secure Boot prompts carefully; follow the MOK enrollment steps when prompted and complete key enrollment on reboot
- ZSH default shell change needs a logout/login
- The VSCodium repository is imported with official GPG key verification (`https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg`).

---

## What Gets Installed

### Core

DNF optimization (parallel downloads, fastest mirror, version pinning), RPM Fusion, Flathub, optional DNS override (Cloudflare or Google), disable auto-sleep (GDM system dconf keyfile + user session), system fonts and FiraCode Nerd Font.

### Shell

ZSH, Starship prompt, zsh-autosuggestions, zsh-syntax-highlighting, eza/bat aliases.

### Power

TLP (optional, warns about GNOME power profiles conflict), ccache (50GB compressed), tuned virtual-host profile for KVM.

### Multimedia & Browsers

Brave Browser, FFmpeg freeworld, VA-API / NVENC support, OpenH264.

### GPU Drivers

Intel media driver, AMD freeworld VA/VDPAU, NVIDIA proprietary (akmods, Secure Boot key enrollment with guided walkthrough).

### Dev Tools

GCC, Clang, LLVM, Java, Node.js, Python, Ruff linter/formatter, PostgreSQL 18, Docker + Docker Compose, Corepack, Code Editor selection (Zed, VS Codium, Antigravity IDE, or VS Code), Rust (optional), Git LFS & git-filter-repo, Android tools, debuggers, build systems.

### Gaming

Steam (with H.264 unlock), MangoHud (auto-configured with 32px HUD scaling, alpha transparency, and rounded corners), Vesktop, and Heroic Games Launcher (native RPM from GitHub Releases for Epic/GOG/sideloaded games, pre-configured with `disableUMU` to eliminate container exit lag, shared wine prefixes, and NVIDIA Prime offload). Included on `gaming`, `full`, and `personal` profiles.

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
