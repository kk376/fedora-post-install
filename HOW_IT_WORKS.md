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
             │   ( set -eo pipefail; $fn )   │
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

- **Subshell Isolation**: Each step executes in a separate subshell `( set -eo pipefail; "$func" )`. A failure inside a step is trapped without crashing the parent orchestrator loop.
- **Reboot Interception**: If a newly installed kernel requires a reboot before compiling out-of-tree drivers, `setup_pre_driver_reboot()` exits with status `100`. The orchestrator intercepts code `100`, marks progress, and terminates execution so the system can restart into the target kernel.
- **Background Sudo Keep-Alive**: In interactive runs, a background daemon runs `sudo -n true` every 60 seconds tied to the script PID (`kill -0 "$$"`), preventing mid-run password timeouts during lengthy DNF operations.

---

## 2. Profile Hierarchy & Layering

Profiles are structured as additive layers over a verified base:

| Profile | Step Count | Target Environment | Key Inclusions |
| :--- | :--- | :--- | :--- |
| `minimal` | 4 steps | Headless / Containers / Servers | DNF5 tuning, DNS resolvers, core CLI tools, shell |
| `workstation` *(default)* | 11 steps | Standard Desktop / Laptops | Minimal + fonts, codecs, desktop apps, power, GPU drivers |
| `dev` | 15 steps | Software Engineering | Workstation + compilers, editors, Docker, KVM/QEMU |
| `gaming` | 12 steps | Gaming Rig | Workstation + Steam, MangoHud, GameMode, Heroic |
| `creator` | 12 steps | Media & Streaming | Workstation + OBS Studio, v4l2loopback, wf-recorder |
| `full` | 17 steps | Complete Workstation | Unifies all steps across all profiles |

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
