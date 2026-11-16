# Technical Architecture & Execution Model

This document outlines the execution lifecycle, profile hierarchy, state management, and safety mechanisms in `fedora-post-install`.

---

## 1. Execution Lifecycle & Process Model

The orchestrator (`main()`) manages pre-flight checks, hardware discovery, profile selection, and step sequencing:

```
                  ┌──────────────────────┐
                  │ Pre-flight & Probing │
                  │  (OSTree, Arch, GPU) │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │   Profile Resolver   │
                  │ (minimal..full steps)│
                  └──────────┬───────────┘
                             │
                             ▼
             ┌───────────────┴───────────────┐
             │ Step Runner (Subshell Loop)   │
             │  ( set -euo pipefail; $fn )   │
             └───────────────┬───────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
       Exit Status 0                 Exit Status 100
     (Mark Step Done)              (Pre-Driver Reboot)
              │                             │
              ▼                             ▼
       Continue to Next Step         Halt Script Cleanly
```

- **Subshell Isolation**: Each step executes in a decoupled subshell `( set -euo pipefail; "$func" )` with explicit status capture. A failure inside a step is trapped without crashing the parent orchestrator loop.
- **Reboot Interception**: If a newly installed kernel requires a reboot before compiling out-of-tree drivers, `setup_pre_driver_reboot()` exits with status `100`. The orchestrator intercepts code `100`, marks progress, and terminates execution so the system can restart into the target kernel.
- **Background Sudo Keep-Alive**: In interactive runs, a background daemon runs `sudo -n true` every 60 seconds tied to the script PID (`kill -0 "$$"`), preventing mid-run password timeouts during lengthy DNF operations.

---

## 2. Profile Hierarchy & Layering

Profiles are structured as additive layers over a verified base:

| Profile | Step Count | Target Environment | Key Inclusions |
| :--- | :--- | :--- | :--- |
| `minimal` | 4 steps | Headless / Containers / Servers | DNF5 tuning, DNS resolvers, core CLI tools, shell |
| `workstation` *(default)* | 12 steps | Standard Desktop / Laptops | Minimal + fonts, codecs, GNOME, debloat, desktop apps, power, GPU drivers |
| `dev` | 16 steps | Software Engineering | Workstation + compilers, editors, Docker, KVM/QEMU |
| `gaming` | 13 steps | Gaming Rig | Workstation + Steam, MangoHud, GameMode, Heroic |
| `creator` | 13 steps | Media & Streaming | Workstation + OBS Studio, v4l2loopback, wf-recorder |
| `full` | 18 steps | Complete Workstation | Unifies all steps across all profiles |

Profiles can be pre-selected via CLI flag `--profile=<name>` or chosen interactively during startup.

---

## 3. Idempotency & State Tracking

Execution state is persisted to `~/.config/fedora-setup/state.txt`.

- **Skip on Re-Run**: Completed steps are recorded in the state manifest. Subsequent runs automatically skip previously completed steps.
- **Force Re-Run**: Passing `--force` (`-f`) ignores the state file and forces re-evaluation of every step in the profile.
- **Dry-Run Mode**: Passing `--dry-run` (`-n`) prints proposed shell commands and configurations without modifying filesystem state or recording progress.

---

## 4. Backup & Disaster Recovery

Before modifying system or user dotfiles, `backup_file()` creates timestamped backups in `~/.config/fedora-setup-backups/<timestamp>/`:

- **Permissions**: Backup directories are strictly restricted to `0700` (`rwx------`).
- **Hierarchy Preservation**: Full file paths are mirrored within the backup directory, and original destinations are cataloged in `.manifest`.
- **Restoration Validation**: Running `--restore` (or selecting restore in pre-flight) validates manifest entries against path traversal (`..`), non-absolute paths, and enforces an allowlist for privileged `/etc/` targets (`dnf.conf`, `zram-generator.conf`). Restoring resets `state.txt` to re-enable clean post-install runs.

---

## 5. Hardware Agnosticism & Platform Discovery

`detect_hardware()` inspects the runtime environment once at initialization:

- **OSTree Detection**: Evaluates `/run/ostree-booted` and immediately halts if run on Fedora Silverblue / Kinoite / Bazzite, which require `rpm-ostree` rather than DNF.
- **Chassis Probing**: Differentiates Laptops, Virtual Machines (`systemd-detect-virt`), Servers, and physical Desktops.
- **GPU Discovery**: Probes PCIe devices via `lspci` and platform DRM devices via `/sys/class/drm/` (supporting Apple Silicon Asahi and ARM SoCs).
- **Driver Gating**: Architecture-specific binaries (`steam`, `intel-compute-runtime`) are restricted to `x86_64`, while ROCm compute runtimes require verified discrete AMD GPUs (`Navi`, `Radeon RX`, `dGPU`).

---

## 6. Source Modularization & Self-Bootstrapping Architecture

Source code is modularized under `src/` to eliminate monolithic code sprawl while providing zero-duplicate clean maintenance:

```
src/
├── 00_header.sh       # Shebang, global configs, hardware variables, colors, logging
├── 01_cli.sh          # Argument parsing (--profile, --dry-run, --dev-type)
├── 02_helpers.sh      # Hardware detection, downloaders, backup/restore
├── 03_profiles.sh     # State tracking, profile selection, preflight diagnostics
├── steps/
│   ├── 01_dnf.sh .. 17_drivers.sh  # 18 domain step modules (including 07b_debloat.sh)
└── 99_main.sh         # Installation summary, orchestrator loop, trap runner
```

- **Dual-Mode Orchestrator (`setup.sh`)**: The root entrypoint is a lean ~50-line self-bootstrapping script:
  1. **Local Mode (Cloned Repository)**: Directly sources runtime and step modules from `./src/` with zero overhead.
  2. **Remote Bootstrap Mode (`curl | bash`)**: When piped from `curl` (where `./src/` does not exist locally), it automatically fetches the lightweight repository archive from GitHub into a temporary sandbox in `/tmp`, executes the suite with all supplied CLI arguments, and cleans up on exit.
- **Optional Release Bundler (`build.sh`)**: Developers and CI can assemble the modular hierarchy into a standalone bundle in `dist/setup.sh` via `make build`.

---

## 7. Debloat Subsystem & Safety Model

`setup_debloat()` provides a structured 4-tier model designed to declutter standard Fedora Workstation installations without compromising desktop stability or unattended safety:

- **Tier 1 (Safe Service Suppression)**: Disables idle network listeners and hardware pollers without impacting core system functions:
  - `rygel`: UPnP media sharing server. Disabled globally (`systemctl --global disable rygel.service`) and for the current user session (`systemctl --user disable --now rygel.service`).
  - `cups-browsed`: Remote CUPS printer discovery daemon (mitigating network exposure and CVE-2024-47176 while preserving local printing).
  - `ModemManager`: Polling daemon conditionally disabled only when no WWAN/cellular modem hardware is detected in `/sys/class/wwan*`.
- **Tier 2 (Desktop Clutter & Office Applications)**: Interactively offers optional removal of heavy pre-installed applications (`libreoffice*`, ~500MB) and unused stock utilities (`gnome-maps`, `gnome-weather`, `gnome-contacts`, `gnome-clocks`, `gnome-characters`, `gnome-logs`, `baobab`, `simple-scan`, `yelp`, `gnome-tour`). Defaults to `N` to prevent unintended removals.
- **Tier 3 (Extreme RAM Optimization)**: Opt-in removal of `gnome-software` and `PackageKit` background daemons. Reclaims 200–400MB of idle memory for developers and gamers who manage packages via `dnf`, `flatpak`, and Extension Manager. Defaults to `N`.
- **Tier 4 (DNF Weak Dependencies)**: Configures `install_weak_deps=False` in `/etc/dnf/dnf.conf` to prevent the automatic installation of non-essential recommended packages during future DNF transactions. Default: `Y`.
- **Unattended Safety Guarantee**: When executed in unattended mode (`--yes` / `-y`), destructive options (Tiers 2 & 3) automatically evaluate to `N`, ensuring headless installations remain fully functional and non-destructive.
