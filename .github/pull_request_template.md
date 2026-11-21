## Description

<!-- Provide a clear, concise summary of the changes proposed in this pull request. -->

## Pull Request Type

<!-- Please check all that apply: -->
- [ ] Bug fix (non-breaking change fixing an existing issue)
- [ ] New feature or package module
- [ ] Hardware detection or architecture enhancement
- [ ] Performance optimization or debloat adjustment
- [ ] Documentation update (README, HOW_IT_WORKS, CHANGELOG)
- [ ] Testing or CI pipeline improvement

---

## Related Issue

<!-- If applicable, link the related issue here: Fixes #123 -->
Fixes #

---

## Affected Modules & Profiles

<!-- List the specific files under src/ or tests/ modified: -->
- **Source Modules**: `src/steps/...` / `src/...`
- **Target Profiles**: `[ ] minimal  [ ] workstation  [ ] dev  [ ] gaming  [ ] creator  [ ] full`

---

## Validation & Quality Checklist

Before submitting your pull request, please verify each of the following:

- [ ] **Modular Edits**: Changes are made within modular files in `src/` (do not manually edit `dist/setup.sh`).
- [ ] **Automated Test Suite**: Ran `make check` locally — all tests pass and ShellCheck emits 0 errors/warnings.
- [ ] **Dry-Run Validation**: Tested your changes with `--dry-run` (`-n`) across affected profiles.
- [ ] **Clean System Verification**: Tested in a clean Fedora VM, container, or live environment.
- [ ] **Defensive Bash Invariants**:
  - Follows 2-space indentation.
  - Quoted variable expansions (`"$VAR"`).
  - Explicit error handling and execution safety.
  - Preserved subshell execution `( set -euo pipefail; ... )`.
- [ ] **Backup Hygiene**: New configuration alterations make proper use of `backup_file()`.
- [ ] **Unattended Safety**: Any destructive or opt-in step defaults to `N` when running with `--yes` (`-y`).
- [ ] **Documentation**: Updated `README.md`, `HOW_IT_WORKS.md`, and `CHANGELOG.md` where appropriate.

---

## Additional Context / Test Output

<!-- Paste relevant dry-run logs, terminal output, or VM test logs demonstrating that the change works as expected. -->
