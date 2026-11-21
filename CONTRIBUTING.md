# Contributing to Fedora Post-Install

Thank you for your interest in improving `fedora-post-install`! Contributions from the Fedora community help keep this script robust, hardware-aware, and secure across releases.

---

## Community Standards & Policies

Please review our community guidelines before participating:

- **[Code of Conduct](.github/CODE_OF_CONDUCT.md)**: We are committed to providing a friendly, safe, and welcoming environment for everyone.
- **[Security Policy](.github/SECURITY.md)**: Read our threat model, privilege boundaries, and instructions for reporting vulnerabilities privately.
- **[Accessibility Statement](.github/ACCESSIBILITY.md)**: Guidelines on screen reader support, `NO_COLOR` terminal compliance, and inclusive UX.

---

## Reporting Issues

- Search [existing issues](https://github.com/kk376/fedora-post-install/issues) to ensure your problem or proposal hasn't already been addressed.
- Use the structured [Bug Report Template](.github/ISSUE_TEMPLATE/bug_report.yml) and include:
  - Fedora version (e.g., Fedora 41 Workstation)
  - Hardware architecture and GPU details (e.g., `x86_64`, NVIDIA RTX 4070 Laptop)
  - Profile executed (`workstation`, `dev`, `gaming`, etc.)
  - Complete terminal output or error logs.

---

## Suggesting Features

- Use the [Feature Request Template](.github/ISSUE_TEMPLATE/feature_request.yml).
- Verify that your proposed package or tool fits the scope of a general post-installation script rather than individual user dotfiles.
- Detail the target profile and package source (official Fedora RPM, RPM Fusion, or Flathub).

---

## Development Workflow & Architecture

`fedora-post-install` is structured as a modular suite under `src/`:

```
src/
├── 00_header.sh       # Global configurations, hardware variables, colors
├── 01_cli.sh          # Argument parsing (--profile, --dry-run, --dev-type)
├── 02_helpers.sh      # Hardware detection, backup/restore engine
├── 03_profiles.sh     # Profile definitions, state tracking, pre-flight checks
├── steps/             # 18 domain-specific installation modules
└── 99_main.sh         # Orchestrator loop, subshell execution, traps
```

### Pull Request Process

1. **Fork & Branch**: Fork the repository and create your feature branch from `main`:
   ```bash
   git checkout -b feat/my-improvement
   ```
2. **Modular Edits**: Make all code modifications in the appropriate files within `src/`. **Never edit `dist/setup.sh` directly**; it is automatically generated from `src/`.
3. **Local Testing & Linting**:
   Run the test and lint pipeline:
   ```bash
   make check
   ```
   This runs ShellCheck against all scripts and executes the automated 7-suite test harness.
4. **Dry-Run Testing**: Test your changes non-destructively:
   ```bash
   bash setup.sh -n --profile=workstation
   ```
5. **Real Environment Testing**: When possible, test on a clean Fedora install, VM (GNOME Boxes / KVM), or container.
6. **Documentation**: Update [README.md](README.md), [HOW_IT_WORKS.md](HOW_IT_WORKS.md), and [CHANGELOG.md](CHANGELOG.md) if your changes introduce new flags, profiles, or modify default behaviors.
7. **Submit PR**: Open a pull request using our [.github/pull_request_template.md](.github/pull_request_template.md).

---

## Code Style & Safety Invariants

- **Indentation**: 2 spaces (no hard tabs).
- **Defensive Scripting**:
  - Quote all variable expansions: `"$VAR"`.
  - Use `set -euo pipefail` in functions and subshells.
  - Test conditions safely (`[[ ... ]]`).
- **Safety Checks**: Never bypass or remove hardware pre-flight checks or OSTree blockers.
- **Backup Hygiene**: Use `backup_file "$target"` before modifying any existing user dotfile or `/etc/` system configuration.
- **Unattended Mode (`-y`) Invariant**: Destructive options in `setup_debloat` (Tiers 2 & 3) must always evaluate to `N` by default during unattended execution.

---

## Questions?

For questions, discussions, or general feedback, please visit [GitHub Discussions](https://github.com/kk376/fedora-post-install/discussions).
