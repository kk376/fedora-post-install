# Security Policy

`fedora-post-install` automates system-level configuration, package installation, kernel driver setup, and desktop customization on Fedora Linux. Because it runs with elevated privileges (`sudo`), maintaining strict security, isolation, and safety invariants is a core project commitment.

---

## Supported Versions

Only the latest major release branch of `fedora-post-install` receives active security fixes and updates.

| Version | Supported | Notes |
| :--- | :--- | :--- |
| `9.x.x` | :white_check_mark: Yes | Current production branch (modular `src/` architecture) |
| `8.x.x` | :x: No | End of Life |
| `< 8.0` | :x: No | End of Life |

### Supported Operating Systems & Environments
- **Fedora Workstation**: Active, non-EOL Fedora releases (Fedora 40, 41, 42, and current Rawhide).
- **Architectures**: `x86_64` and `aarch64`.
- **Unsupported / Explicitly Blocked**: Immutable OSTree-based distributions (Fedora Silverblue, Kinoite, Bazzite, CoreOS). The script detects `/run/ostree-booted` and halts immediately to avoid conflicts with `rpm-ostree`.

---

## Security Invariants & Threat Model

1. **Explicit Privilege Boundaries**:
   - The script must **never** be run directly as `root` (e.g., `sudo setup.sh`). Running as root breaks user-scoped environment paths (`$HOME`), user systemd units, and D-Bus session buses.
   - Root elevation is strictly isolated to specific administrative tasks (`dnf`, `/etc/` system configuration, drivers) via explicit `sudo` calls.
   - An interactive background keep-alive (`sudo -n true`) is tied strictly to the script's PID (`kill -0 "$$"`) and automatically terminates on script exit.

2. **Execution & Subshell Isolation**:
   - Step modules execute within isolated subshells: `( set -euo pipefail; "$func" )`.
   - A runtime error inside any step is trapped cleanly without contaminating parent environment variables or crashing the orchestrator loop.

3. **Backup & Path Traversal Protections**:
   - Before modifying any system or dotfile, timestamped copies are saved to `~/.config/fedora-setup-backups/<timestamp>/`.
   - Backup directories are permissions-restricted to `0700` (`rwx------`).
   - The restoration engine validates `.manifest` paths against directory traversal (`..`), rejects relative paths, and restricts `/etc/` restoration to an explicit allowlist.

4. **Non-Destructive Defaults in Unattended Mode**:
   - When run with `--yes` (`-y`), potentially destructive debloat actions (such as removing LibreOffice or PackageKit) are automatically set to `N`.

5. **Remote Bootstrapper Sandbox Integrity**:
   - When run via `curl -fsSL ... | bash`, `setup.sh` downloads the repository archive into an ephemeral, permission-restricted directory in `/tmp`, validates the payload, executes with user-supplied arguments, and enforces an automatic cleanup trap on exit (`EXIT INT TERM`).

---

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability or privilege escalation flaw in `fedora-post-install`:

1. **GitHub Security Advisory (Preferred)**:
   Navigate to the repository's **[Security tab](https://github.com/kk376/fedora-post-install/security/advisories)** and click **"Report a vulnerability"** to open a private advisory.

2. **Direct Maintainer Email**:
   Email Kushagra Kumar directly at **[kkushagra86@gmail.com](mailto:kkushagra86@gmail.com)** with the subject line `[SECURITY] fedora-post-install: <Short Summary>`.

### What to Include in Your Report
To help us triage and resolve the issue quickly, please provide:
- A description of the vulnerability and its potential security impact.
- The affected version, profile, and command flags (e.g., `v9.0.0`, `--profile=dev`).
- Step-by-step instructions or proof-of-concept commands to reproduce the issue.
- Any suggested remediations or patches if you have one.

### Response & Disclosure Process
- **Initial Response**: We will acknowledge receipt of your vulnerability report within **48 hours**.
- **Assessment**: We will evaluate the report, verify the impact, and keep you updated on progress within **7 days**.
- **Coordinated Disclosure**: A patch will be developed, tested against all CI suites, and published along with an advisory crediting your discovery (unless you request anonymity).
