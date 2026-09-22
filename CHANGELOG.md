# Changelog

All notable changes to this project will be documented in this file.

Follows semantic versioning: MAJOR.MINOR.PATCH

## [v5.8.0] - 2026-09-22

### Added

- **GPU Terminal Emulator Selection & Dev-Suite Config Sync**: Added interactive selection in developer and full profiles for modern GPU-accelerated terminal emulators (Ghostty recommended as default, Kitty, or Alacritty) with automated deployment of Tokyo Night configurations directly from the `dev-suite` repository.
- **Personal Profile Ghostty Automation**: Automated the installation and configuration of Ghostty with author configs and GTK styling from `dev-suite` in the `personal` profile without interactive prompts.

### Changed

- **Heroic Games Launcher Flathub Migration**: Swapped Heroic Games Launcher from DNF RPM to the official Flathub Flatpak (`com.heroicgameslauncher.hgl`) as recommended by the upstream development team. Deployed optimized settings (`disableUMU: true`, `showMangohud: true`, NVIDIA Prime offload, and shared Wine prefix tree) directly to `~/.var/app/com.heroicgameslauncher.hgl/config/heroic/config.json`.
- **Decoupled Terminal Prompt**: Removed Kitty terminal emulator prompt from unconditional profile execution, keeping stock Ptyxis for minimal, workstation, gaming, and creator profiles.

## [v5.7.0] - 2026-09-21

### Added

- **Hybrid Graphics Vulkan Loader Optimization**: Deployed `/etc/environment.d/10-vulkan-hybrid.conf` automatically on hybrid laptops (AMD+NVIDIA or Intel+NVIDIA), setting `VK_LOADER_DRIVERS_SELECT` to match the integrated GPU (`*radeon*` or `*intel*`). This prevents GTK4 and Libadwaita applications (Files, Settings, Text Editor) from probing the discrete NVIDIA GPU and triggering an ACPI D3cold to D0 hardware power transition, eliminating 2+ second cold launch freezes while preserving on-demand discrete GPU offloading via `switcheroo-control` for games and compute.

## [v5.6.0] - 2026-09-19

### Added

- **System-Wide High-Definition Bluetooth Audio**: Deployed `/etc/wireplumber/wireplumber.conf.d/50-bluez.conf` system-wide, prioritizing high-resolution codecs (LDAC, AAC, aptX, SBC-XQ), enabling wideband speech (mSBC), and enforcing hardware volume synchronization. Roles are explicitly stabilized to `[ a2dp_sink a2dp_source hfp_hf hfp_ag ]` to eliminate SDP negotiation resets on Bluetooth Classic audio devices.
- **Bit-Perfect Dynamic Sample-Rate Clocking**: Deployed `/etc/pipewire/pipewire.conf.d/99-clock-rates.conf` system-wide, unlocking dynamic sample-rate switching across `[ 44100 48000 88200 96000 176400 192000 ]` Hz across all user profiles to eliminate lossy software resampling.
- **GNOME Top Bar Live Clock**: Configured the GNOME top bar clock in the `personal` profile to display live seconds and weekday (`clock-show-seconds = true`, `clock-show-weekday = true`).
- **Personal Profile ONLYOFFICE Integration**: Added automated removal of `libreoffice*` and native installation of `onlyoffice-desktopeditors` RPM in the `personal` profile for 1:1 Microsoft Office document fidelity.

### Security & Hardening

- **Download Protocol Security**: Enforced `--proto '=https' --tlsv1.2` across `curl` commands downloading external installer scripts (`starship`, `zed`, `antigravity`) to eliminate protocol downgrade attacks and block non-HTTPS redirects.
- **PowerPointViewer HTTPS Migration**: Switched Microsoft PowerPointViewer cabinet archive download URL from plaintext HTTP to secure HTTPS.
- **Verified Binary Download for `cliamp`**: Replaced unverified `curl | sh` execution from GitHub `HEAD` with direct binary download and verification via `github_download()`.

## [v5.5.8] - 2026-09-14

### Added

- **Complete Microsoft Office Font Suite**: Added automated extraction and installation of modern **Aptos** (the default body typeface across Microsoft 365 since late 2023, including Regular, Bold, Italic, Light, Semibold, ExtraBold, Black, Narrow, Mono, and Serif variants), **Cambria Regular** (`cambria.ttc`, including Cambria Math extracted from Microsoft PowerPointViewer cabinet archives to solve the upstream Linux installer omission), and **Segoe UI** into `~/.local/share/fonts/ms-fonts/`.
- **Caladea Metric Twin for Cambria**: Added `google-crosextra-caladea-fonts` to the system DNF package list to provide native metric-compatible serif substitution in LibreOffice and OpenOffice.
- **Personal Profile ONLYOFFICE Swap**: Added automatic removal of default `libreoffice*` packages and installation of native `onlyoffice-desktopeditors` RPM from ONLYOFFICE for seamless 1:1 Microsoft Office compatibility in the author's bespoke `personal` profile.

### Changed

- **Process Monitor Modernization**: Replaced `htop` with modern `btop` in the essential packages list.

## [v5.5.7] – 2026-09-09

### Added

- **Full Freeworld HEVC & E-AC3 Codec Suite**: Explicitly installs `gstreamer1-plugins-bad-freeworld` (providing `libde265` and `svt-hevc`), `gstreamer1-plugins-ugly`, `gstreamer1-vaapi`, and full RPM Fusion `ffmpeg-libs`, solving VLC *"Codec not supported: hevc / eac3"* errors.
- **AMD Hardware VA-API Acceleration**: Robust installation of `mesa-va-drivers-freeworld` across AMD GPU setups for full hardware-accelerated H.264/H.265 video decode.

## [v5.5.6] – 2026-09-09

### Added

- **Heroic Games Launcher (Native RPM)**: Integrated official GitHub release RPM download and installation of Heroic Games Launcher into gaming profiles (`gaming`, `full`, `personal`).
- **Wine Prefix Initialization**: Pre-creates standard wine prefix directories (`$HOME/Games/Heroic/Prefixes/shared`) during setup to eliminate file picker errors on initial game addition.
- **Heroic & UMU Optimization**: Pre-seeds and updates Heroic configuration with `"disableUMU": true` (eliminating container teardown delay on game exit), `"showMangohud": true`, and auto-detects NVIDIA hybrid GPUs for `"nvidiaPrime": true`.
- **MangoHud Scaling & Sync**: Configured MangoHud overlay with `font_size=32`, `background_alpha=0.4`, and `round_corners=8`, with automated configuration synchronization to Flatpak Heroic environments.
- **GNOME Mutter Hang Watchdog Disable**: Configured `org.gnome.mutter check-alive-timeout 0` in GNOME setup to prevent false-positive "Window is not responding" freeze dialogs during initial Wine/Proton shader compilation pauses.

### Removed

- **ProtonPlus Flatpak**: Removed `com.vysp3r.ProtonPlus` from `setup_flatpaks()`. Heroic Games Launcher includes a native, built-in Wine & Proton Manager (supporting Wine-GE, GE-Proton, CachyOS Proton, DXVK, and VKD3D directly with zero extra dependencies), rendering external compatibility managers redundant.

## [v5.5.5] – 2026-09-07

### Added

- **Interactive Profile Menu**: Running `./setup.sh` directly without command-line arguments presents an interactive menu to choose your profile (`minimal`, `workstation`, `gaming`, `creator`, `dev`, `full`, or `personal`). If `dev` is selected, an interactive submenu allows selecting developer genres (`systems`, `web`, `android`, `ai`, or `all`). Defaults to `full` profile when pressing Enter or in non-interactive/dry-run contexts.
- **Personal Profile Media Suite**: Added `cliamp` (retro TUI music player preconfigured for YouTube Music via Chrome keyring cookies) and `ani-cli` (anime streaming CLI with patched provider) to the author's bespoke `personal` profile.

### Changed

- **Usage Documentation**: Simplified `README.md` Usage to focus on interactive execution (`./setup.sh`), dry-run preview (`./setup.sh --dry-run`), and forced re-runs (`./setup.sh --force`), removing cumbersome manual CLI profile flags in favor of the interactive menu.

## [v5.5.0] – 2026-09-07

### Added

- **Dev Profile Genres (`--dev-type=GENRE`)**:
  - `systems`: C, C++, Rust toolchain (rustup, clippy, rust-analyzer), CMake, Meson, Ninja, GDB, Valgrind, Hyperfine
  - `web`: Node.js runtime, Corepack package manager integration (pnpm, yarn), Python 3, Docker, jq
  - `android`: `android-tools` (ADB/Fastboot), Scrcpy device mirror, Java OpenJDK latest & devel, Maven, Android Studio (Flathub), KVM virtualization permissions
  - `ai`: Python 3 development headers, virtualenv, wheel, Ruff linter/formatter, and **Hardware-Gated NVIDIA CUDA Failsafe**
  - `all`: Comprehensive developer stack (default)
  - Supports CLI flag `--dev-type=GENRE` (comma-separated or single) and interactive prompt
- **Hardware-Gated NVIDIA CUDA Failsafe**: Probes PCI hardware via `lspci`; if NVIDIA GPU is detected, prompts for CUDA development packages; if AMD or Intel GPU is detected, safely skips with informational notice explaining vendor-specific acceleration (e.g. AMD ROCm)
- **Personal Profile (`--profile=personal`)**: Dedicated 17-step profile isolating author's bespoke workflow (PostgreSQL 18 server daemon, pgAdmin 4 desktop, 50GB ccache, dpkg-dev, X11 dev headers, kkfetch) from the public `full` profile
- **Host Asset Integration**:
  - `akmod-v4l2loopback`: Integrated in `creator`, `full`, and `personal` profiles for OBS Studio virtual camera functionality
  - `gnome-shell-extension-appindicator`: Added to GNOME setup for system tray icon support
  - `gamemode`: Added to `gaming`, `full`, and `personal` profiles
  - `kk376/kkfetch`: Added to COPR repositories (`setup_copr`)
  - `plocate`, `tree`, `compsize`: Added to base package suite
- **Fish Shell & Autosuggestion Contrast Polish**: Full Fish shell deployment alongside ZSH and Bash in `setup_shell`, featuring Starship prompt, FZF keybindings, custom aliases, and tuned `#828bb8` autosuggestion styling

### Changed

- **Purged Mission Center**: Completely eradicated `io.missioncenter.MissionCenter` (which causes PCIe bus lockups and GPU sleep freezes on MUXless hybrid GPU laptops). Replaced with GNOME Extension Manager (`com.mattjakeman.ExtensionManager`).
- **Orthogonal Profile Matrix**:
  - `minimal` (7 steps): Unchanged core base
  - `workstation` (11 steps): Removed Steam, MangoHud, and KVM for clean productivity desktop
  - `creator` (11 steps): Focused on OBS Studio, V4L2 loopback, GStreamer, and NV Broadcast (removed KVM)
  - `gaming` (11 steps): Pinned to Steam, MangoHud, GameMode, ProtonPlus, Vesktop
  - `dev` (16 steps): Developer tools with genre filtering, Flatpaks (Android Studio), Docker, KVM
  - `full` (17 steps): Complete public power-user superset
  - `personal` (17 steps): Full suite + author's bespoke PostgreSQL 18, 50GB ccache, kkfetch, dpkg-dev
- **Gated Gaming Flatpaks**: ProtonPlus (`com.vysp3r.ProtonPlus`) is strictly gated on gaming-capable profiles (`gaming`, `full`, `personal`)

---

## [v5.4.0] – 2026-09-01

### Added

- **Interactive Prompts & Decision Guidance for Niche Utilities**:
  - **Scrcpy**: Interactive confirmation with feature summary (Android screen mirroring & control over USB/Wi-Fi) and recommendation guidance in `setup_copr`
  - **Yazi**: Interactive confirmation with feature summary (blazing fast terminal file manager in Rust) and recommendation guidance in `setup_copr`
  - **Vesktop**: Interactive confirmation with feature summary (Discord client with screen share audio & Vencord) and recommendation guidance in `setup_packages`
  - **Stirling-PDF**: Interactive confirmation with feature summary (offline local web-based PDF suite) and recommendation guidance in `setup_packages`
  - **NVIDIA Broadcast for Linux**: Interactive confirmation with feature summary (AI microphone noise suppression & speaker cleanup) and recommendation guidance in `setup_packages`
  - **VirtIO Windows VM Guest Drivers (`virtio-win`)**: Interactive confirmation with guidance for users running Windows guest VMs in `setup_kvm`
- **SHA256 Checksum Verification**: Added `verify_checksum()` helper function for cryptographic download integrity verification

### Changed

- **Profile Isolation for COPR & Debian Toolchains**:
  - Isolated COPR repositories (`setup_copr`) exclusively to the `full` profile (removed from `creator` profile, keeping creator to a clean 12-step flow)
  - Isolated `dpkg-dev` (Debian/Ubuntu package building toolchain) strictly to the `full` profile in `setup_dev()`
- **Repository Cloning Optimization**: Pinned shallow `--depth 1` git clone for third-party source repos

### Removed

- **Android ROM / AOSP / Kernel & 32-bit Multilib Development Stack**:
  - Removed AOSP ROM build dependencies (`schedtool`, `lzop`, `pngcrush`, `squashfs-tools`, `gperf`, `sdl12-compat-devel`) from `setup_dev()`
  - Removed 32-bit multilib development libraries (`glibc-devel.i686`, `libstdc++-devel.i686`, `zlib-ng-compat-devel.i686`, `libX11-devel.i686`, `readline-devel.i686`, `ncurses-devel.i686`) from `setup_dev()` (retaining `android-tools` in `setup_packages` for ADB/Fastboot device connectivity)

### Security

- Removed insecure `trust_all_worktrees` directive from embedded Zed configuration template

---

## [v5.3.0] – 2026-08-30

### Added

- **Interactive Code Editor Selection (`setup_editor`)**: Multi-choice selection in `dev` and `full` profiles offering Zed (Recommended), VS Codium, Anti gravity IDE, VS Code (Not recommended), and an option to skip, complete with tailored configuration deployment
- **Interactive Zed Runner (`~/.local/bin/zed-run`)**: Universal multi-language execution script (Python, Rust, C, C++, Go, JS, TS, Bash, Lua, HTML) featuring a `Ctrl+C` interrupt trap (`INT`/`TERM`) that smoothly drops to an interactive ZSH subshell
- **Ruff Python Tooling**: Added `ruff` (extreme performance Python linter and formatter) directly to essential DNF development packages
- **PostgreSQL 18 & pgAdmin 4**: Added official PGDG RPM repository (`pgdg-fedora-repo`), automated `postgresql18-server` install, cluster `initdb`, systemd activation, environment PATH (`/etc/profile.d/pgsql18.sh`), and `pgadmin4-desktop` via official pgAdmin repository
- **Kitty Terminal Suite**: Integrated Kitty terminal configuration with translucent dark glass aesthetics (font size 13, opacity 0.90, blur 50, top tab bar navigation)
- **WirePlumber Bluetooth HD Audio**: Deployed configuration for high-resolution Bluetooth codecs (LDAC, AptX, AAC) with automatic profile switching
- **Git History & Sanitization Tooling**: Added `git-filter-repo` to development package dependencies for history rewriting and repository sanitization
- **Desktop & Creator Utilities**: Integrated Stirling-PDF offline utility suite, GSConnect firewall rules, and NVIDIA Broadcast AI noise reduction for creator setups

### Changed

- Updated profile matrices (`dev` and `full`) and execution sequence to replace legacy editor steps with `setup_editor`
- Configured DNF with `defaultyes=True` for streamlined package transactions
- Standardized Zed installation on the official installer script (`https://zed.dev/install.sh`) without third-party repository dependencies

### Security

- Hardened `.gitignore` with defensive patterns against committing environment files (`.env*`), SSH/GPG keys, and secret credential bundles

---

## [v5.2.0] – 2026-08-18

### Changed

- Replaced Oh My Zsh and Powerlevel10k with Starship prompt (`starship`) and standalone ZSH plugins (`zsh-autosuggestions`, `zsh-syntax-highlighting`), deploying a pre-configured `~/.config/starship.toml` and clean `.zshrc`
- Enabled DNS configuration (`setup_dns`) across all profiles (`minimal`, `dev`, `gaming`, `workstation`, `creator`, `full`) with an informational banner explaining benefits and network considerations (default: Cloudflare 1.1.1.1, option 2: Google 8.8.8.8)
- Refactored GDM login screen no-sleep settings to write `/etc/dconf/db/gdm.d/01-power` and run `dconf update`, eliminating D-Bus session and SELinux permission errors from `sudo -u gdm dbus-run-session`
- Filtered Steam and MangoHud package installation, Steam H.264 codec unlock, and `MangoHud.conf` deployment to gaming and desktop profiles (`gaming`, `workstation`, `creator`, `full`), skipping them on headless and minimal profiles
- Standardized all six profiles to uniformly include the pre-driver reboot checkpoint (`setup_pre_driver_reboot`) and GPU driver setup (`setup_drivers`) at the end of their execution flow

### Added

- Comprehensive Secure Boot and MOK enrollment guidance and disclaimer in `setup_drivers` detailing manual signing steps, `akmods` local key management, and UEFI firmware update handling
- Custom developer `.zshrc` profile with WSL Antigravity IDE (`anti`) helper, NVM integration, and history optimizations

### Removed

- Removed obsolete COPR repository for `eza` in `setup_copr()` as it is available directly in Fedora's official repositories and installed via `setup_packages()`
- Removed Cloudflare Warp step (`setup_warp`) and associated summary checks to streamline setup and avoid upstream repository instability

---

## [v5.1.0] – 2026-08-17

### Changed

- Moved GPU driver setup (`setup_drivers`) from step 8 to the final step, after all packages, tools, and services are installed and configured
- Gaming and creator profile step ordering updated to match
- Swapped awk variable passing in `set_zshrc_line` to use `ENVIRON` to prevent backslash unescaping issues on regex patterns

### Added

- `setup_pre_driver_reboot`: automatic reboot checkpoint before driver setup. Compares the running kernel against the latest installed kernel (from `dnf update`). If they differ, prompts the user to reboot first so `akmods` builds NVIDIA modules against the correct kernel. On re-run, the state file skips all completed steps and resumes at driver setup.
- Automated test suites under `tests/` covering profile step integrity, CLI options matrix, helper functions, and backup/restore subsystems (135 tests)

### Fixed

- Fixed tilde expansion issue in ZSH custom plugin clone paths by standardizing to `$HOME/.oh-my-zsh/custom`
- Corrected package names for Yazi in COPR setup (`ripgrep`, `fd-find`, `poppler-utils`) and added `--skip-unavailable`
- Ensured `warp-svc` service is started before attempting `warp-cli` registration
- Added `unzip` package to `setup_fonts` before font archive extraction
- Added pipefail error safeguards to `check_disk_space`, `setup_pre_driver_reboot`, and Vesktop release tag parsing
- Locally scoped GPU and chassis variables in `setup_drivers`

---

## [v5.0.3] – 2026-08-16

### Changed

- Replaced Discord with Vesktop in `setup_packages()`: Discord was previously silently skipped by `dnf` because it is not available in official Fedora repos; Vesktop is now automatically downloaded and installed via its official GitHub release `.rpm` with fallback and architecture detection
- Added `vesktop` to `show_versions()` installed package checks

---

## [v5.0.2] – 2026-08-15

### Improved

- Refactored `setup_copr()` into an array-driven loop across repositories, eliminating duplicated enable/install logic
- Streamlined step filtering and counting in `main()` into a single array pass instead of iterating twice
- Standardized command output redirections (`&>/dev/null`) and cleaned up section headers

### Removed

- Unused dead functions (`reset_state()`, redundant `cleanup()`, unused color variables)
- Inlined single-use `check_version()` logic into `show_versions()`
- Removed broken `emergency_rollback()` error trap which evaluated exit status incorrectly due to local variable scoping
- Removed redundant `validate_step()` calls

---

## [v5.0.1] – 2026-08-14

### Fixed

- Progress counter no longer counts failed or skipped steps as completed — `show_summary` now reports completed/failed/skipped separately instead of one number
- `MangoHud.conf` and `.bashrc` are now backed up before being modified, matching what `restore_backups()` already expected to find
- `setup_copr` and the Antigravity install no longer swallow failures silently (`A && B || true` replaced with explicit warnings on failure)
- Antigravity CLI install in dev tools was targeting a nonexistent npm package and failing silently every time; now installs via Google's official installer (`curl -fsSL https://antigravity.google/cli/install.sh | bash`, binary `agy`)
- Steam H264 unlock now kills only the specific process it launched instead of `pkill -f "xdg-open"`, which could match unrelated processes on the system
- `.zshrc` theme/plugins lines are now set via a verified replace-or-append helper (`set_zshrc_line`) instead of relying on `sed`'s exit code, which returns 0 whether or not anything actually matched
- Disk space check now warns explicitly when it can't determine free space, instead of silently falling through to "OK" with a blank value
- Removed stale `code` version check from `show_versions` (leftover from before the switch to Antigravity); checks `agy` instead

### Changed

- Antigravity repo file still uses `gpgcheck=0` — this matches Google's own official Fedora/RHEL install instructions, which don't currently publish a signing key for the RPM repo (their APT instructions do). Rather than leave that undisclosed, the script now warns about it explicitly when the step runs.

### Docs

- README profile table now lists `multimedia` under the `gaming` profile, matching what the profile actually installs (it was already running `setup_browser_multimedia`, just not documented)

---

## [v5.0.0] – 2026-08-14

### Added

- Updated for Fedora 44
- Antigravity CLI in dev tools (replaces discontinued Gemini CLI)
- MangoHud config folded into the packages step (auto-configures if mangohud is present)
- Reusable `github_download()` helper for GitHub release fetches

### Removed

- Gemini CLI is discontinued; replaced by Antigravity CLI in dev tools
- OnlyOffice step (LibreOffice ships with Fedora)
- Winboat step (too niche)
- LM Studio step (AppImage wrangling; use Ollama instead)
- MangoHud config as a standalone step (moved into packages)
- preload from COPR (negligible benefit on SSDs)
- ani-cli from COPR (too niche)
- Yaru theme prompt (Ubuntu theme on Fedora is uncommon)

### Improved

- Profiles updated to match the leaner step list
- Deduplicated gsettings calls in no-sleep setup
- Simplified Docker service management (removed redundant enable/start calls)
- ccache config no longer appends duplicate lines on re-run
- Corepack moved from Docker step to dev tools where it belongs
- Fixed `nvim` package name to `neovim`
- Simplified confirm prompt function
- Cleaned up script header

---

## [v4.0.0] – 2026-01-21

### Added

- KVM/QEMU virtualization module with modern socket activation (`virtqemud.socket`)
- `workstation` profile (Dev + Virtualization + Office) and `creator` profile (Gaming + Multimedia + AI)
- Rollback on failure: stops services, preserves state, points to logs
- Disk space check before starting (warns if <20GB free)
- Version pinning via `best=True` in DNF operations
- Network validation before remote operations

### Improved

- DNF config uses `best=True` and atomic RPM Fusion installation
- Better error handling with state preservation for resumption
- Modern libvirt socket activation instead of legacy service
- Documentation updated for new features and troubleshooting

### Fixed

- Progress counter in dry-run mode
- Service management during emergency rollback
- User group handling for Docker and libvirt
- Profile step filters for new profiles

---

## [v3.0.0] – 2026-01-17

### Added

- Profile system: `--profile=minimal|dev|gaming|full`
- State file (`~/.config/fedora-setup/state.txt`) for idempotency
- `--force` flag to re-run completed steps
- DNS provider choice (Google, Cloudflare, or skip)
- TLP opt-in with GNOME power profiles warning
- RPM Fusion validation before multimedia step
- Dynamic step counting based on profile

### Improved

- NVIDIA Secure Boot flow: `akmods --force` + `modinfo` check before MOK enrollment
- DNF config uses `# BEGIN/END fedora-setup` block markers for clean idempotency
- More specific GPU detection patterns (VGA|3D|Display)
- Dry-run skips DNS step; progress counters only increment in real runs
- State file reset after backup restore

### Removed

- Unused `check_existing_config()` function
- `alsa-plugins-pulseaudio` (unnecessary on PipeWire)

---

## [v2.0.2] – 2026-01-16

### Added

- Enabled `fedora-cisco-openh264` repository for OpenH264 availability

---

## [v2.0.1] – 2026-01-16

### Fixed

- Typo in `keepcache` in dnf.conf

---

## [v2.0.0] – 2026-01-16

### Added

- Backup/restore for config files before modification
- Dry-run mode to preview actions without touching the system
- Logging to file for debugging
- Post-step validation for each major step
- Version and state checks to avoid redundant work

### Improved

- Script safety and predictability
- Idempotency of installation steps
- Error visibility and troubleshooting

### Notes

- v2.0 is a breaking change internally due to new execution flow
- Review dry-run output before upgrading from v1.x

---

## [v1.0.0] – Initial Release

### Added

- Interactive Fedora post-install script
- DNF optimization and repository setup
- TLP power management with boot-time fix
- GPU driver detection (Intel / AMD / NVIDIA with Secure Boot)
- ZSH + Powerlevel10k setup
- Multimedia, gaming, and dev environment configuration
- Cloudflare Warp, Docker, Antigravity integration
