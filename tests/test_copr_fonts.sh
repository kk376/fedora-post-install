#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088
# ==============================================================================
# Test Suite: COPR & Fonts Subsystem (v7.0.0)
# Covers:
#   1. COPR repository mappings (scrcpy in setup_dev, yazi in setup_desktop_apps)
#   2. COPR preview dependencies and enable safety
#   3. setup_fonts package list (MS, Noto, Liberation, DejaVu, FiraCode Nerd Font)
#   4. setup_fonts FiraCode download, unzip, and fc-cache execution
#   5. Dry-run safety for setup_fonts
#   6. Profile inclusion verification (creator, full, minimal, dev, gaming, workstation)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="${SCRIPT_DIR}/setup.sh"

TOTAL=0
PASSED=0
FAILED=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() {
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    echo -e "  [${GREEN}PASS${NC}] $1"
}

fail() {
    TOTAL=$((TOTAL + 1))
    FAILED=$((FAILED + 1))
    echo -e "  [${RED}FAIL${NC}] $1"
    [[ -n "${2:-}" ]] && echo "         Detail: $2"
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$label"
    else
        fail "$label" "Expected: '$expected', Actual: '$actual'"
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$label"
    else
        fail "$label" "Expected output to contain '$needle'"
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        pass "$label"
    else
        fail "$label" "Expected output NOT to contain '$needle'"
    fi
}

echo "================================================================"
echo "TEST SUITE: COPR & Fonts Subsystem Audit (v7.0.0)"
echo "Target: $SETUP_SCRIPT"
echo "================================================================"

# ==============================================================================
# Suite 1: COPR Static & Configuration Audit
# ==============================================================================
echo ""
echo -e "${BLUE}=== Suite 1: COPR Configuration Audit ===${NC}"

# Check scrcpy COPR in setup_dev
if grep -A 10 "setup_dev()" "$SETUP_SCRIPT" | grep -q 'copr enable -y zeno/scrcpy' || \
   grep -q 'copr enable -y zeno/scrcpy' "$SETUP_SCRIPT"; then
    pass "setup.sh enables zeno/scrcpy COPR repository for Android tooling"
else
    fail "setup.sh missing zeno/scrcpy COPR repository"
fi

# Check yazi COPR in setup_desktop_apps
if grep -q 'copr enable -y lihaohong/yazi' "$SETUP_SCRIPT"; then
    pass "setup.sh enables lihaohong/yazi COPR repository for Yazi file manager"
else
    fail "setup.sh missing lihaohong/yazi COPR repository"
fi

# Check Ghostty COPR in setup_terminal
if grep -q 'copr enable -y scottames/ghostty' "$SETUP_SCRIPT"; then
    pass "setup.sh enables scottames/ghostty COPR repository for Ghostty terminal"
else
    fail "setup.sh missing scottames/ghostty COPR repository"
fi

# Verify yazi preview dependencies in setup_desktop_apps
yazi_install_line=$(grep -A 5 'copr enable -y lihaohong/yazi' "$SETUP_SCRIPT" | grep 'dnf install')
required_yazi_deps=("yazi" "file" "poppler-utils" "resvg" "ImageMagick")
for dep in "${required_yazi_deps[@]}"; do
    assert_contains "Yazi dependency '$dep' present in install list" "$dep" "$yazi_install_line"
done

# ==============================================================================
# Suite 2: COPR Runtime Dry-Run Behavior
# ==============================================================================
echo ""
echo -e "${BLUE}=== Suite 2: COPR Runtime Dry-Run Behavior ===${NC}"

dry_full=$(bash "$SETUP_SCRIPT" --dry-run -f --profile=full 2>&1)
assert_contains "Full profile dry-run logs Yazi COPR enable" "sudo dnf copr enable -y lihaohong/yazi" "$dry_full"
assert_contains "Full profile dry-run logs Yazi install" "sudo dnf install -y --skip-unavailable yazi" "$dry_full"
assert_contains "Full profile dry-run logs Scrcpy COPR enable" "sudo dnf copr enable -y zeno/scrcpy" "$dry_full"
assert_contains "Full profile dry-run logs Scrcpy install" "sudo dnf install -y --skip-unavailable scrcpy" "$dry_full"

# ==============================================================================
# Suite 3: setup_fonts Static Package Audit
# ==============================================================================
echo ""
echo -e "${BLUE}=== Suite 3: setup_fonts Static Package Audit ===${NC}"

fonts_func_code=$(sed -n '/^setup_fonts() {/,/^}/p' "$SETUP_SCRIPT")

# 1. DejaVu fonts
assert_contains "setup_fonts installs dejavu-sans-fonts" "dejavu-sans-fonts" "$fonts_func_code"
assert_contains "setup_fonts installs dejavu-serif-fonts" "dejavu-serif-fonts" "$fonts_func_code"
assert_contains "setup_fonts installs dejavu-sans-mono-fonts" "dejavu-sans-mono-fonts" "$fonts_func_code"

# 2. Liberation fonts
assert_contains "setup_fonts installs liberation-sans-fonts" "liberation-sans-fonts" "$fonts_func_code"
assert_contains "setup_fonts installs liberation-serif-fonts" "liberation-serif-fonts" "$fonts_func_code"
assert_contains "setup_fonts installs liberation-mono-fonts" "liberation-mono-fonts" "$fonts_func_code"

# 3. Google Noto fonts & metric-compatible MS substitutes
assert_contains "setup_fonts installs google-noto-sans-fonts" "google-noto-sans-fonts" "$fonts_func_code"
assert_contains "setup_fonts installs google-noto-serif-fonts" "google-noto-serif-fonts" "$fonts_func_code"
assert_contains "setup_fonts installs google-noto-mono-fonts" "google-noto-mono-fonts" "$fonts_func_code"
assert_contains "setup_fonts installs google-carlito-fonts" "google-carlito-fonts" "$fonts_func_code"
assert_contains "setup_fonts installs google-caladea-fonts" "google-caladea-fonts" "$fonts_func_code"

# 4. Microsoft fonts
assert_contains "setup_fonts downloads msttcore-fonts-installer" "msttcore-fonts-installer-2.6-1.noarch.rpm" "$fonts_func_code"
assert_contains "setup_fonts verifies msttcore-fonts checksum" "verify_checksum" "$fonts_func_code"
assert_contains "setup_fonts installs cabextract for MS core fonts" "cabextract" "$fonts_func_code"
assert_contains "setup_fonts cleans up msttcore-fonts rpm after install" "rm -f" "$fonts_func_code"
assert_contains "setup_fonts downloads PowerPointViewer for Cambria Regular" "PowerPointViewer.exe" "$fonts_func_code"
assert_contains "setup_fonts extracts cambria.ttc" "cambria.ttc" "$fonts_func_code"
assert_contains "setup_fonts installs Aptos font family" "ttf-aptos" "$fonts_func_code"
assert_contains "setup_fonts installs Segoe UI font family" "segoe-ui-linux" "$fonts_func_code"

# 5. FiraCode Nerd Font parameters
assert_contains "setup_fonts targets ryanoasis/nerd-fonts repo" "ryanoasis/nerd-fonts" "$fonts_func_code"
assert_contains "setup_fonts uses FiraCode regex pattern" 'FiraCode\\.zip' "$fonts_func_code"
assert_contains "setup_fonts outputs to /tmp/FiraCode.zip" "/tmp/FiraCode.zip" "$fonts_func_code"
assert_contains "setup_fonts provides fallback URL" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" "$fonts_func_code"
assert_contains "setup_fonts unpacks to ~/.local/share/fonts" "HOME/.local/share/fonts" "$fonts_func_code"
assert_contains "setup_fonts cleans up temporary zip" "rm -f /tmp/FiraCode.zip" "$fonts_func_code"

# 6. fc-cache execution
assert_contains "setup_fonts executes fc-cache -fv" "fc-cache -fv" "$fonts_func_code"

# ==============================================================================
# Suite 4: setup_fonts Runtime & Dry-Run Safety
# ==============================================================================
echo ""
echo -e "${BLUE}=== Suite 4: setup_fonts Runtime & Dry-Run Safety ===${NC}"

# Test DRY_RUN=true safety
test_fonts_dry_run() {
    local func_code="$1"
    bash <<EOF
set -u
DRY_RUN=true
REAL_EXEC_COUNT=0

log() { :; }
info() { :; }
warn() { :; }
step_complete() { :; }
dry() { echo "DRY: \$1"; }
run() { dry "\$*"; }
run_sudo() { dry "sudo \$*"; }
confirm() { return 0; }
github_download() { ((REAL_EXEC_COUNT++)); return 0; }
fc-cache() { ((REAL_EXEC_COUNT++)); return 0; }
mkdir() { ((REAL_EXEC_COUNT++)); return 0; }
unzip() { ((REAL_EXEC_COUNT++)); return 0; }
tar() { ((REAL_EXEC_COUNT++)); return 0; }

$func_code

setup_fonts

echo "REAL_EXEC_COUNT=\$REAL_EXEC_COUNT"
EOF
}

dry_run_out=$(test_fonts_dry_run "$fonts_func_code")
assert_contains "Dry-run makes zero real filesystem or cache modifications" "REAL_EXEC_COUNT=0" "$dry_run_out"
assert_contains "Dry-run logs DNF font install" "DRY: sudo dnf install -y --skip-unavailable" "$dry_run_out"
assert_contains "Dry-run logs msttcore-fonts curl download" "DRY: curl -fsSL -o" "$dry_run_out"
assert_contains "Dry-run logs Cambria, Aptos, and Segoe UI download" "Download Cambria, Aptos, and Segoe UI" "$dry_run_out"
assert_contains "Dry-run logs FiraCode Nerd Font download/extract" "DRY: Download and extract FiraCode Nerd Font and Symbols Nerd Font" "$dry_run_out"
assert_contains "Dry-run logs fc-cache -fv" "DRY: fc-cache -fv" "$dry_run_out"

# Test DRY_RUN=false execution flow (mocked tools)
test_fonts_live_execution() {
    local func_code="$1"
    bash <<EOF
set -u
DRY_RUN=false

log() { :; }
info() { :; }
warn() { :; }
success() { echo "SUCCESS: \$1"; }
step_complete() { echo "STEP: \$1"; }
run() { echo "RUN: \$*"; }
run_sudo() { echo "SUDO: \$*"; }
mkdir() { echo "MKDIR: \$*"; }
unzip() { echo "UNZIP: \$*"; }
tar() { echo "TAR: \$*"; }
rm() { echo "RM: \$*"; }
fc-cache() { echo "FC-CACHE: \$*"; }
confirm() { return 0; }
verify_checksum() { return 0; }
curl() { echo "CURL: \$*"; return 0; }
cabextract() { echo "CABEXTRACT: \$*"; return 0; }

github_download() {
    echo "GH_DOWNLOAD: repo=\$1 pattern=\$2 output=\$3 fallback=\$4"
    return 0
}

$func_code

setup_fonts
EOF
}

live_exec_out=$(test_fonts_live_execution "$fonts_func_code")
assert_contains "Live mode creates font directories" "MKDIR: -p $HOME/.local/share/fonts/FiraCode" "$live_exec_out"
assert_contains "Live mode downloads FiraCode" "GH_DOWNLOAD: repo=ryanoasis/nerd-fonts pattern=FiraCode\\.zip output=/tmp/FiraCode.zip" "$live_exec_out"
assert_contains "Live mode unzips font archive" "UNZIP: -oq /tmp/FiraCode.zip -d $HOME/.local/share/fonts/FiraCode/" "$live_exec_out"
assert_contains "Live mode removes temporary zip" "RM: -f /tmp/FiraCode.zip" "$live_exec_out"
assert_contains "Live mode downloads Symbols Nerd Font" "GH_DOWNLOAD: repo=ryanoasis/nerd-fonts pattern=NerdFontsSymbolsOnly\\.tar\\.xz" "$live_exec_out"
assert_contains "Live mode signals Symbols Nerd Font success" "SUCCESS: Symbols Nerd Font installed" "$live_exec_out"
assert_contains "Live mode executes fc-cache -fv" "FC-CACHE: -fv" "$live_exec_out"
assert_contains "Live mode signals FiraCode success" "SUCCESS: FiraCode Nerd Font installed" "$live_exec_out"
assert_contains "Live mode finishes font setup step" "STEP: Fonts installed" "$live_exec_out"

# ==============================================================================
# Suite 5: Profile Inclusions
# ==============================================================================
echo ""
echo -e "${BLUE}=== Suite 5: Profile Inclusions for Fonts ===${NC}"

# Parse PROFILE_STEPS from setup.sh
declare -A PROFILE_STEPS
eval "$(sed -n '/local base_minimal=/,/PROFILE_STEPS\[full\]=/p' "$SETUP_SCRIPT" | sed 's/local -A /declare -g -A /; s/local /declare -g /')"

# setup_fonts must be in all graphical profiles
for prof in workstation dev gaming creator; do
    if [[ "${PROFILE_STEPS[$prof]}" == *"setup_fonts"* ]]; then
        pass "Profile '$prof' includes setup_fonts"
    else
        fail "Profile '$prof' includes setup_fonts" "Steps: ${PROFILE_STEPS[$prof]}"
    fi
done

# setup_fonts must be excluded from minimal
if [[ "${PROFILE_STEPS[minimal]}" != *"setup_fonts"* ]]; then
    pass "Profile 'minimal' excludes setup_fonts (CLI/headless focus)"
else
    fail "Profile 'minimal' should NOT include setup_fonts" "Steps: ${PROFILE_STEPS[minimal]}"
fi

# Full profile check
steps_definitions=$(sed -n '/local steps=(/,/)/p' "$SETUP_SCRIPT")
if [[ "$steps_definitions" == *"\"setup_fonts:System & Nerd Fonts\""* ]]; then
    pass "Full profile master registry includes setup_fonts"
else
    fail "Full profile master registry includes setup_fonts"
fi

# ==============================================================================
# Final Summary
# ==============================================================================
echo ""
echo "================================================================"
echo "Final Summary: Total: $TOTAL, Passed: $PASSED, Failed: $FAILED"
echo "================================================================"

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
