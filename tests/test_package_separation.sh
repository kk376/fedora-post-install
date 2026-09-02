#!/usr/bin/env bash
# Test Suite for Package & App Separation
# Tests package distribution in setup_packages and setup_copr in setup.sh:
# 1. steam, mangohud, Steam H264 unlock, and MangoHud config profile gating
# 2. vesktop installation for non-minimal profiles
# 3. eza inclusion in DNF packages and removal from COPR

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="${SCRIPT_DIR}/setup.sh"

PASSED=0
FAILED=0
TOTAL=0

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

echo "================================================================"
echo "TEST SUITE: Package & App Separation Tester"
echo "Target Script: $SETUP_SCRIPT"
echo "================================================================"

# ==============================================================================
# Suite 1: Static Code Analysis Checks
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 1: Static Code Analysis ---${NC}"

# 1.1 eza in DNF packages in setup_packages
if grep -A 10 "setup_packages()" "$SETUP_SCRIPT" | grep -q "eza"; then
    pass "eza is present in setup_packages() DNF package list"
else
    fail "eza is NOT present in setup_packages() DNF package list"
fi

# 1.2 eza NOT in setup_copr()
if sed -n '/setup_copr()/,/^}/p' "$SETUP_SCRIPT" | grep -q "eza"; then
    fail "eza found in setup_copr() (should be removed from COPR)"
else
    pass "eza is NOT present in setup_copr() COPR repositories"
fi

# 1.3 COPR entries contain scrcpy and yazi
if sed -n '/setup_copr()/,/^}/p' "$SETUP_SCRIPT" | grep -q "zeno/scrcpy" && \
   sed -n '/setup_copr()/,/^}/p' "$SETUP_SCRIPT" | grep -q "lihaohong/yazi"; then
    pass "setup_copr() contains expected COPR entries (scrcpy, yazi)"
else
    fail "setup_copr() missing expected COPR repositories"
fi

# 1.4 Steam and MangoHud profile gating logic check in setup_packages
gating_check=$(sed -n '/setup_packages()/,/^}/p' "$SETUP_SCRIPT" | grep -E 'is_gaming_profile|PROFILE.*==.*(gaming|workstation|creator|full)')
if [[ -n "$gating_check" ]]; then
    pass "setup_packages() contains profile gate for gaming/workstation/creator/full"
else
    fail "setup_packages() missing profile gating for gaming packages"
fi

# ==============================================================================
# Suite 2: Profile Workflow & Step Separation
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 2: Profile Workflow Separation ---${NC}"

# Extract steps for each profile from setup.sh
get_steps_for_profile() {
    local target_profile="$1"
    bash -c '
        info() { :; }
        log() { :; }
        warn() { :; }
        error() { :; }
        init_state() { :; }
        confirm() { return 1; }

        code=$(sed -n "/local steps=(/,/TOTAL_STEPS=/p" "$2")
        code=$(echo "$code" | sed "s/local -A /declare -g -A /g; s/local /declare -g /g")
        PROFILE="$1"
        eval "$code"

        filtered_steps=()
        for step in "${steps[@]}"; do
            IFS=":" read -r func _ <<< "$step"
            if [[ -z "${PROFILE_STEPS[$PROFILE]}" ]] || [[ " ${PROFILE_STEPS[$PROFILE]} " =~ " $func " ]]; then
                filtered_steps+=("$func")
            fi
        done
        echo "${filtered_steps[*]}"
    ' _ "$target_profile" "$SETUP_SCRIPT"
}

minimal_steps=$(get_steps_for_profile "minimal")
dev_steps=$(get_steps_for_profile "dev")
gaming_steps=$(get_steps_for_profile "gaming")
workstation_steps=$(get_steps_for_profile "workstation")
creator_steps=$(get_steps_for_profile "creator")
full_steps=$(get_steps_for_profile "full")

# 2.1 minimal skips setup_packages and setup_copr
if [[ ! " $minimal_steps " =~ " setup_packages " ]]; then
    pass "minimal profile excludes setup_packages"
else
    fail "minimal profile should NOT include setup_packages"
fi

if [[ ! " $minimal_steps " =~ " setup_copr " ]]; then
    pass "minimal profile excludes setup_copr"
else
    fail "minimal profile should NOT include setup_copr"
fi

# 2.2 Non-minimal profiles include setup_packages
for p in "dev" "gaming" "workstation" "creator" "full"; do
    steps_var=$(get_steps_for_profile "$p")
    if [[ " $steps_var " =~ " setup_packages " ]]; then
        pass "Profile '$p' includes setup_packages"
    else
        fail "Profile '$p' missing setup_packages"
    fi
done

# 2.3 COPR step is only in full profile
for p in "minimal" "dev" "gaming" "workstation" "creator"; do
    steps_var=$(get_steps_for_profile "$p")
    if [[ ! " $steps_var " =~ " setup_copr " ]]; then
        pass "Profile '$p' excludes setup_copr"
    else
        fail "Profile '$p' should NOT include setup_copr"
    fi
done

for p in "full"; do
    steps_var=$(get_steps_for_profile "$p")
    if [[ " $steps_var " =~ " setup_copr " ]]; then
        pass "Profile '$p' includes setup_copr"
    else
        fail "Profile '$p' missing setup_copr"
    fi
done

# ==============================================================================
# Suite 3: Mock Execution Tests for setup_packages
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 3: Mock Execution of setup_packages ---${NC}"

# Function to run setup_packages in an isolated environment with mocks
run_mock_setup_packages() {
    local target_profile="$1"
    local sandbox
    sandbox=$(mktemp -d)

    bash -c '
        set -u
        PROFILE="$1"
        sandbox="$2"
        setup_script="$3"

        DRY_RUN=false
        HOME="$sandbox"
        BACKUP_DIR="$sandbox/backups"
        LOG_FILE="$sandbox/test.log"

        log() { :; }
        info() { :; }
        warn() { :; }
        error() { :; }
        success() { :; }
        step_complete() { :; }
        backup_file() { :; }
        confirm() { return 0; }

        run_sudo() {
            if [[ "$1" == "dnf" && "$2" == "install" ]]; then
                shift 2
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        -y|--skip-unavailable) shift ;;
                        /tmp/vesktop.rpm) touch "$sandbox/.vesktop_installed"; shift ;;
                        *) echo -n "$1 " >> "$sandbox/.dnf_pkgs"; shift ;;
                    esac
                done
                return 0
            elif [[ "$1" == "dnf" && "$2" == "config-manager" ]]; then
                return 0
            fi
            "$@"
        }

        run() {
            "$@"
        }

        # Mock flatpak & steam & xdg-open & sleep
        flatpak() { return 1; }
        steam() {
            if [[ "$*" == *"steam://unlockh264/"* ]]; then
                touch "$sandbox/.steam_unlocked"
            fi
            builtin sleep 0.05
        }
        xdg-open() {
            if [[ "$*" == *"steam://unlockh264/"* ]]; then
                touch "$sandbox/.steam_unlocked"
            fi
            builtin sleep 0.05
        }
        mangohud() { return 0; }
        command() {
            if [[ "$1" == "-v" && "$2" == "mangohud" ]]; then
                return 0
            elif [[ "$1" == "-v" && "$2" == "vesktop" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        rpm() { return 1; }
        curl() { return 0; }
        git() { return 0; }
        lspci() { return 0; }
        github_download() {
            touch "$3"
            return 0
        }
        sleep() { command sleep 0.05; }

        # Extract profile helpers and setup_packages definitions from setup.sh
        eval "$(sed -n "/is_gaming_profile() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/is_creator_profile() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/setup_packages() {/,/^}/p" "$setup_script")"

        # Execute setup_packages
        setup_packages

        # Output state
        echo -n "DNF_PKGS:"
        [[ -f "$sandbox/.dnf_pkgs" ]] && cat "$sandbox/.dnf_pkgs"
        echo ""
        echo "STEAM_UNLOCKED:$([[ -f "$sandbox/.steam_unlocked" ]] && echo true || echo false)"
        echo "MANGOHUD_CONFIGURED:$([[ -f "$sandbox/.config/MangoHud/MangoHud.conf" ]] && echo true || echo false)"
        echo "VESKTOP_INSTALLED:$([[ -f "$sandbox/.vesktop_installed" ]] && echo true || echo false)"
    ' _ "$target_profile" "$sandbox" "$SETUP_SCRIPT"

    rm -rf "$sandbox"
}

# Test gaming packages in gaming, workstation, creator, full profiles
for prof in "gaming" "workstation" "creator" "full"; do
    output=$(run_mock_setup_packages "$prof")
    dnf_pkgs=$(echo "$output" | grep "^DNF_PKGS:" | cut -d: -f2-)
    steam_unlocked=$(echo "$output" | grep "^STEAM_UNLOCKED:" | cut -d: -f2)
    mangohud_conf=$(echo "$output" | grep "^MANGOHUD_CONFIGURED:" | cut -d: -f2)
    vesktop_inst=$(echo "$output" | grep "^VESKTOP_INSTALLED:" | cut -d: -f2)

    # 1. steam & mangohud in DNF
    if [[ " $dnf_pkgs " =~ " steam " && " $dnf_pkgs " =~ " mangohud " ]]; then
        pass "Profile '$prof': steam and mangohud included in DNF packages"
    else
        fail "Profile '$prof': steam or mangohud missing from DNF packages (got: $dnf_pkgs)"
    fi

    # 2. eza in DNF
    if [[ " $dnf_pkgs " =~ " eza " ]]; then
        pass "Profile '$prof': eza included in DNF packages"
    else
        fail "Profile '$prof': eza missing from DNF packages"
    fi

    # 3. Steam H264 unlock
    if [[ "$steam_unlocked" == "true" ]]; then
        pass "Profile '$prof': Steam H264 codec unlock executed"
    else
        fail "Profile '$prof': Steam H264 codec unlock was NOT executed"
    fi

    # 4. MangoHud configuration
    if [[ "$mangohud_conf" == "true" ]]; then
        pass "Profile '$prof': MangoHud config file created"
    else
        fail "Profile '$prof': MangoHud config file was NOT created"
    fi

    # 5. Vesktop installation
    if [[ "$vesktop_inst" == "true" ]]; then
        pass "Profile '$prof': Vesktop RPM download & install executed"
    else
        fail "Profile '$prof': Vesktop was NOT installed"
    fi
done

# Test dev profile (must NOT include steam/mangohud or their configs, but MUST include eza and vesktop)
echo ""
echo -e "${BLUE}--- Suite 4: Mock Execution for Dev Profile ---${NC}"
dev_output=$(run_mock_setup_packages "dev")
dev_dnf_pkgs=$(echo "$dev_output" | grep "^DNF_PKGS:" | cut -d: -f2-)
dev_steam_unlocked=$(echo "$dev_output" | grep "^STEAM_UNLOCKED:" | cut -d: -f2)
dev_mangohud_conf=$(echo "$dev_output" | grep "^MANGOHUD_CONFIGURED:" | cut -d: -f2)
dev_vesktop_inst=$(echo "$dev_output" | grep "^VESKTOP_INSTALLED:" | cut -d: -f2)

if [[ ! " $dev_dnf_pkgs " =~ " steam " ]]; then
    pass "Profile 'dev': steam is excluded from DNF packages"
else
    fail "Profile 'dev': steam should NOT be installed in dev profile"
fi

if [[ ! " $dev_dnf_pkgs " =~ " mangohud " ]]; then
    pass "Profile 'dev': mangohud is excluded from DNF packages"
else
    fail "Profile 'dev': mangohud should NOT be installed in dev profile"
fi

if [[ " $dev_dnf_pkgs " =~ " eza " ]]; then
    pass "Profile 'dev': eza is included in DNF packages"
else
    fail "Profile 'dev': eza missing from DNF packages"
fi

if [[ "$dev_steam_unlocked" == "false" ]]; then
    pass "Profile 'dev': Steam H264 codec unlock is NOT executed"
else
    fail "Profile 'dev': Steam H264 codec unlock should NOT be executed"
fi

if [[ "$dev_mangohud_conf" == "false" ]]; then
    pass "Profile 'dev': MangoHud config is NOT created"
else
    fail "Profile 'dev': MangoHud config should NOT be created"
fi

if [[ "$dev_vesktop_inst" == "true" ]]; then
    pass "Profile 'dev': Vesktop RPM download & install executed"
else
    fail "Profile 'dev': Vesktop was NOT installed in dev profile"
fi

# ==============================================================================
# Suite 5: Mock Execution of setup_copr
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 5: Mock Execution of setup_copr ---${NC}"

run_mock_setup_copr() {
    local sandbox
    sandbox=$(mktemp -d)

    bash -c '
        set -u
        sandbox="$1"
        setup_script="$2"
        DRY_RUN=false

        log() { :; }
        info() { :; }
        warn() { :; }
        error() { :; }
        success() { :; }
        step_complete() { :; }
        confirm() { return 0; }

        run_sudo() {
            if [[ "$1" == "dnf" && "$2" == "copr" && "$3" == "enable" ]]; then
                echo -n "$5 " >> "$sandbox/.copr_repos"
                return 0
            elif [[ "$1" == "dnf" && "$2" == "install" ]]; then
                shift 2
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        -y|--skip-unavailable) shift ;;
                        *) echo -n "$1 " >> "$sandbox/.copr_pkgs"; shift ;;
                    esac
                done
                return 0
            fi
            return 0
        }

        # Extract setup_copr definition from setup.sh
        eval "$(sed -n "/setup_copr() {/,/^}/p" "$setup_script")"

        setup_copr

        echo -n "COPR_REPOS:"
        [[ -f "$sandbox/.copr_repos" ]] && cat "$sandbox/.copr_repos"
        echo ""
        echo -n "COPR_PKGS:"
        [[ -f "$sandbox/.copr_pkgs" ]] && cat "$sandbox/.copr_pkgs"
        echo ""
    ' _ "$sandbox" "$SETUP_SCRIPT"

    rm -rf "$sandbox"
}

copr_output=$(run_mock_setup_copr)
copr_repos=$(echo "$copr_output" | grep "^COPR_REPOS:" | cut -d: -f2-)
copr_pkgs=$(echo "$copr_output" | grep "^COPR_PKGS:" | cut -d: -f2-)

if [[ " $copr_repos " =~ " zeno/scrcpy " && " $copr_repos " =~ " lihaohong/yazi " ]]; then
    pass "setup_copr enables scrcpy and yazi COPR repositories"
else
    fail "setup_copr missing expected repositories (got: $copr_repos)"
fi

if [[ " $copr_pkgs " =~ " scrcpy " && " $copr_pkgs " =~ " yazi " ]]; then
    pass "setup_copr installs scrcpy and yazi packages"
else
    fail "setup_copr missing scrcpy or yazi package install (got: $copr_pkgs)"
fi

if [[ ! " $copr_repos " =~ " eza " && ! " $copr_pkgs " =~ " eza " ]]; then
    pass "setup_copr does NOT enable or install eza via COPR"
else
    fail "setup_copr unexpectedly references eza"
fi

# ==============================================================================
# Suite 6: MangoHud Configuration Content Integrity
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 6: MangoHud Configuration Integrity ---${NC}"

test_mangohud_content() {
    local sandbox
    sandbox=$(mktemp -d)

    bash -c '
        set -u
        PROFILE="gaming"
        DRY_RUN=false
        sandbox="$1"
        setup_script="$2"
        HOME="$sandbox"
        BACKUP_DIR="$sandbox/backups"
        LOG_FILE="$sandbox/test.log"

        log() { :; }
        info() { :; }
        warn() { :; }
        error() { :; }
        success() { :; }
        step_complete() { :; }
        backup_file() { :; }
        confirm() { return 0; }
        run_sudo() { return 0; }
        run() { return 0; }
        flatpak() { return 1; }
        steam() { return 0; }
        mangohud() { return 0; }
        command() { return 0; }
        rpm() { return 1; }
        curl() { return 0; }
        git() { return 0; }
        lspci() { return 0; }
        github_download() { touch "$3"; return 0; }
        sleep() { return 0; }

        eval "$(sed -n "/is_gaming_profile() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/is_creator_profile() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/setup_packages() {/,/^}/p" "$setup_script")"
        setup_packages
    ' _ "$sandbox" "$SETUP_SCRIPT"

    local conf_file="$sandbox/.config/MangoHud/MangoHud.conf"
    if [[ -f "$conf_file" ]]; then
        local content
        content=$(cat "$conf_file")
        if grep -q "gpu_stats" "$conf_file" && \
           grep -q "cpu_stats" "$conf_file" && \
           grep -q "fps" "$conf_file"; then
            pass "MangoHud.conf content is valid and contains expected metrics"
        else
            fail "MangoHud.conf content missing expected metrics: $content"
        fi
    else
        fail "MangoHud.conf was not created"
    fi

    rm -rf "$sandbox"
}

test_mangohud_content

# ==============================================================================
# Suite 7: Dry-Run Safety
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 7: Dry-Run Safety ---${NC}"

# Test that dry-run for gaming prints expected dry messages and does not modify filesystem
dry_output=$(bash "$SETUP_SCRIPT" --dry-run -f --profile=gaming 2>&1)

if echo "$dry_output" | grep -q "Unlock Steam H264 codec"; then
    pass "Dry-run gaming profile logs Steam H264 unlock action"
else
    fail "Dry-run gaming profile missing Steam H264 unlock log"
fi

if echo "$dry_output" | grep -q "MangoHud.conf"; then
    pass "Dry-run gaming profile logs MangoHud.conf creation"
else
    fail "Dry-run gaming profile logs MangoHud.conf creation"
fi

if echo "$dry_output" | grep -q "Download and install Vesktop RPM"; then
    pass "Dry-run gaming profile logs Vesktop RPM download action"
else
    fail "Dry-run gaming profile missing Vesktop download log"
fi

dry_dev_output=$(bash "$SETUP_SCRIPT" --dry-run -f --profile=dev 2>&1)
if ! echo "$dry_dev_output" | grep -q "Unlock Steam H264 codec" && \
   ! echo "$dry_dev_output" | grep -q "Create MangoHud.conf"; then
    pass "Dry-run dev profile does NOT log Steam H264 unlock or MangoHud config"
else
    fail "Dry-run dev profile unexpectedly logged gaming actions"
fi

if echo "$dry_dev_output" | grep -q "Download and install Vesktop RPM"; then
    pass "Dry-run dev profile logs Vesktop RPM download action"
else
    fail "Dry-run dev profile missing Vesktop download log"
fi

# ==============================================================================
# Suite 8: Kitty Terminal Emulator Option
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 8: Kitty Terminal Emulator Option ---${NC}"

# 8.1: Test setup_packages does NOT unconditionally include kitty in DNF packages
if grep -A 10 "setup_packages()" "$SETUP_SCRIPT" | grep -w "pkgs_to_install" | grep -q "kitty"; then
    fail "kitty found in setup_packages() (should be optional in setup_shell)"
else
    pass "kitty is NOT unconditionally included in setup_packages() DNF list"
fi

# 8.2: Test setup_shell prompt logic for Kitty
if grep -q 'confirm "Install and configure Kitty terminal emulator?"' "$SETUP_SCRIPT"; then
    pass "setup_shell prompts user for Kitty terminal installation"
else
    fail "setup_shell missing Kitty confirmation prompt"
fi

# 8.3: Test dry-run logs Kitty confirmation prompt
if echo "$dry_dev_output" | grep -q "Prompt: Install and configure Kitty terminal emulator?"; then
    pass "Dry-run dev profile logs Kitty confirmation prompt"
else
    fail "Dry-run dev profile missing Kitty confirmation prompt log"
fi

# ==============================================================================
# Suite 9: AOSP/Multilib Removal & dpkg-dev Profile Isolation
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 9: AOSP/Multilib Removal & dpkg-dev Profile Isolation ---${NC}"

# 9.1: Verify android-tools is included in setup_packages for phone connectivity/debugging
pkgs_to_install_array=$(sed -n '/setup_packages()/,/^}/p' "$SETUP_SCRIPT" | sed -n '/local pkgs_to_install=(/,/)/p')
if echo "$pkgs_to_install_array" | grep -q "android-tools"; then
    pass "android-tools is included in setup_packages() for Android device connectivity"
else
    fail "android-tools missing from setup_packages()"
fi

# 9.2: Verify AOSP build packages removed from setup_dev
for aosp_pkg in "schedtool" "lzop" "pngcrush" "squashfs-tools" "gperf" "sdl12-compat-devel"; do
    if grep -A 15 "setup_dev()" "$SETUP_SCRIPT" | grep -w "dev_pkgs" | grep -q "$aosp_pkg"; then
        fail "AOSP package '$aosp_pkg' unexpectedly present in setup_dev()"
    else
        pass "AOSP package '$aosp_pkg' is excluded from setup_dev()"
    fi
done

# 9.3: Verify 32-bit multilib packages removed from setup_dev
for multilib_pkg in "glibc-devel.i686" "libstdc++-devel.i686" "zlib-ng-compat-devel.i686" "libX11-devel.i686" "readline-devel.i686" "ncurses-devel.i686"; do
    if grep -A 15 "setup_dev()" "$SETUP_SCRIPT" | grep -q "$multilib_pkg"; then
        fail "Multilib package '$multilib_pkg' unexpectedly present in setup_dev()"
    else
        pass "Multilib package '$multilib_pkg' is excluded from setup_dev()"
    fi
done

# 9.4: Verify full profile only dev packages (dpkg-dev, GUI/audio development libraries)
dev_pkgs_array=$(sed -n '/setup_dev()/,/^}/p' "$SETUP_SCRIPT" | sed -n '/local dev_pkgs=(/,/)/p')
for full_only_pkg in "dpkg-dev" "libX11-devel" "libxkbcommon-x11-devel" "libxcb-devel" "fontconfig-devel" "alsa-lib-devel"; do
    if echo "$dev_pkgs_array" | grep -q "$full_only_pkg"; then
        fail "$full_only_pkg is unconditionally present in dev_pkgs"
    else
        pass "$full_only_pkg is not in unconditional dev_pkgs array"
    fi

    if grep -A 10 '\[\[ "\$PROFILE" == "full" \]\]' "$SETUP_SCRIPT" | grep -q "$full_only_pkg"; then
        pass "$full_only_pkg is strictly gated on PROFILE=full"
    else
        fail "$full_only_pkg is missing full profile gate in setup_dev"
    fi
done

echo ""
echo "================================================================"
echo "SUMMARY: Total Tests: $TOTAL, Passed: $PASSED, Failed: $FAILED"
echo "================================================================"

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
