# Accessibility Statement

`fedora-post-install` is committed to providing an accessible, inclusive, and transparent post-installation experience for all Fedora Linux users. Whether you interact with this project via a terminal emulator, assistive screen reader (such as Orca), a braille display, or keyboard-only navigation, this document outlines our accessibility standards, design invariants, and reporting channels.

---

## Command-Line & Terminal Usability

### 1. Screen Reader & Braille Display Compatibility
- **Sequential Plain-Text Prompts**: Interactive choices use explicit, numbered menus and standard `[Y/n]` confirmations.
- **No Disruptive Overwrites or Spinners**: The script avoids ANSI cursor-repositioning hacks, full-screen terminal redraws, or animated ASCII spinners that can flood screen readers or cause erratic line-jumps on braille displays.
- **Descriptive Status Indicators**: All progress logs include clear text prefixes (`[OK]`, `[INFO]`, `[WARN]`, `[ERROR]`, `[DRY-RUN]`) in addition to visual colors.

### 2. High Contrast & `NO_COLOR` Support
- **Color Invariants**: Colors are strictly supplementary; no interface state or error message is conveyed by color alone.
- **`NO_COLOR` Standard**: Fully complies with the [no-color.org](https://no-color.org/) standard. When the `NO_COLOR` environment variable is present (or `TERM=dumb`), all ANSI escape codes and styling are suppressed automatically.

### 3. Non-Interactive & Fatigue-Reducing Execution
- **One-Command Unattended Runs**: For users with motor impairments or those who find repetitive prompts fatiguing, full automation is supported via CLI flags:
  ```bash
  # Pre-select profile and approve prompts automatically
  ./setup.sh --profile=workstation -y
  ```
- **Auditable Dry-Run Mode**: Users can inspect all proposed commands before anything executes on disk using `--dry-run` (`-n`).

---

## Desktop & GNOME Integration

When running desktop configuration modules:

1. **Accessibility Daemon Preservation**:
   The interactive debloat engine (`setup_debloat`) **never** disables or modifies GNOME accessibility daemons, including `at-spi2-core`, the `orca` screen reader, sticky keys, screen magnifier, or high-contrast theme components.
2. **Typography & Readability**:
   Step `06_fonts.sh` installs modern, highly legible fonts (Adwaita Sans, Adwaita Mono, variable Noto fonts, and COLRv1 color emojis) to enhance readability and glyph coverage across diverse displays and scaling ratios.

---

## Reporting Accessibility Barriers

If you encounter an accessibility barrier—such as unannounced prompts, hard-to-read formatting, terminal emulator conflicts, or screen reader incompatibility:

1. **GitHub Issues**:
   Open an issue on the [Issues Tracker](https://github.com/kk376/fedora-post-install/issues) and mention accessibility in the title or apply the `accessibility` label.
2. **Direct Contact**:
   Email the maintainer at **[kkushagra86@gmail.com](mailto:kkushagra86@gmail.com)** with `[A11Y]` in the subject line.

Please include:
- Assistive technology and version (e.g., Orca 47, brltty, Alacritty with high-contrast theme).
- The command and flags you executed.
- The barrier encountered and expected behavior.

We treat accessibility bugs with the same urgency as functional regressions.
