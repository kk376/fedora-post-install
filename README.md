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

---

## What's New in v5.3.0

- **Code Editor Selection:** Added interactive editor setup (`setup_editor`) offering four tailored options: Zed (Recommended, with custom keymaps and interactive runner), VS Codium (FLOSS VS Code binary), Anti gravity IDE (Google AI development suite), and VS Code (proprietary Microsoft build), along with an option to skip.
- **Interactive Zed Runner:** Deployed `~/.local/bin/zed-run` with `Ctrl+C` interrupt trapping, keeping an interactive shell open across Python, Rust, C/C++, Go, JS, TS, Bash, and Lua executions.
- **Ruff Python Tooling:** Added `ruff` directly to the essential DNF packages list for instant, high-performance linting and formatting alongside standard Python symlinks.
- **PostgreSQL 18 & pgAdmin 4:** Integrated official PostgreSQL PGDG and pgAdmin repositories, automated cluster `initdb`, systemd service enablement, and PATH configuration.
- **Kitty Terminal Suite:** Deployed modern Kitty terminal configuration with dark glass transparency, blur, tab navigation, and matching GNOME window headerbars.
- **Bluetooth HD Audio:** Added WirePlumber configuration for high-resolution Bluetooth codecs (LDAC, AptX, AAC) with automatic profile switching.
- **Desktop & Creator Utilities:** Integrated Stirling-PDF offline utility suite, GSConnect firewall rules, and NVIDIA Broadcast AI noise reduction for creator setups.

See [CHANGELOG.md](CHANGELOG.md) for the full history.

---

## Usage

```bash
# Full profile, interactive
./setup.sh

# Preview without changes
./setup.sh --dry-run

# Pick a profile
./setup.sh --profile=minimal
./setup.sh --profile=dev
./setup.sh --profile=gaming
./setup.sh --profile=workstation
./setup.sh --profile=creator

# Re-run already-completed steps
./setup.sh --force
```

### Profiles

| Profile       | What it installs                                                                                             |
| ------------- | ------------------------------------------------------------------------------------------------------------ |
| `minimal`     | DNF config, DNS, fonts, shell (Starship), Brave & codecs, GPU drivers (last)                                 |
| `dev`         | Minimal + power, no-sleep, GNOME tools, dev tools, Code Editor (Zed/Codium/Antigravity/Code), Docker, KVM/QEMU, GPU drivers (last) |
| `gaming`      | Minimal + power, GNOME tools, gaming packages (Steam, MangoHud, Vesktop), Flatpaks, GPU drivers (last)       |
| `workstation` | Minimal + power, GNOME tools, packages, Flatpaks, KVM/QEMU, GPU drivers (last)                               |
| `creator`     | Gaming + COPR tools (Yazi, Scrcpy), KVM/QEMU, GPU drivers (last)                                            |
| `full`        | All steps: DNF, DNS, power, no-sleep, fonts, shell, codecs, COPR, GNOME, packages, dev, Code Editor, Flatpaks, Docker, KVM, GPU drivers (last) |

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

Steam (with H.264 unlock), MangoHud (auto-configured if installed), ProtonPlus. Included on `gaming`, `workstation`, `creator`, and `full` profiles.

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

Each step prompts before running.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines and testing instructions.

## License

MIT. See [LICENSE](LICENSE).
