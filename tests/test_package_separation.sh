#!/usr/bin/env bash
# shellcheck disable=SC2016
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

# 1.1 eza in DNF packages in setup_cli_core
if grep -A 10 "setup_cli_core()" "$SETUP_SCRIPT" | grep -q "eza"; then
    pass "eza is present in setup_cli_core() DNF package list"
else
    fail "eza is NOT present in setup_cli_core() DNF package list"
fi

# 1.2 eza NOT in COPR repositories
if grep -i "copr" "$SETUP_SCRIPT" | grep -q "eza"; then
    fail "eza found in COPR repositories (should be standard DNF package)"
else
    pass "eza is NOT present in COPR repositories"
fi

# 1.3 COPR entries contain scrcpy and yazi
if grep -q "zeno/scrcpy" "$SETUP_SCRIPT" && \
   grep -q "lihaohong/yazi" "$SETUP_SCRIPT"; then
    pass "setup.sh contains expected COPR entries (scrcpy, yazi)"
else
    fail "setup.sh missing expected COPR repositories"
fi

# 1.4 Steam and MangoHud domain step isolation
if grep -A 10 "setup_gaming()" "$SETUP_SCRIPT" | grep -qE "steam|mangohud|gamemode" && \
   grep -A 10 "setup_creator()" "$SETUP_SCRIPT" | grep -q "akmod-v4l2loopback"; then
    pass "Domain packages (gaming: steam/mangohud, creator: akmod-v4l2loopback) are isolated to dedicated steps"
else
    fail "Domain packages missing proper step isolation"
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

# 2.1 minimal skips desktop_apps and gaming
if [[ ! " $minimal_steps " =~ " setup_desktop_apps " ]]; then
    pass "minimal profile excludes setup_desktop_apps"
else
    fail "minimal profile should NOT include setup_desktop_apps"
fi

if [[ ! " $minimal_steps " =~ " setup_gaming " ]]; then
    pass "minimal profile excludes setup_gaming"
else
    fail "minimal profile should NOT include setup_gaming"
fi

# 2.2 Non-minimal profiles include setup_desktop_apps
for p in "dev" "gaming" "workstation" "creator" "full"; do
    steps_var=$(get_steps_for_profile "$p")
    if [[ " $steps_var " =~ " setup_desktop_apps " ]]; then
        pass "Profile '$p' includes setup_desktop_apps"
    else
        fail "Profile '$p' missing setup_desktop_apps"
    fi
done

# 2.3 Gaming step isolation across profiles
for p in "minimal" "dev" "workstation" "creator"; do
    steps_var=$(get_steps_for_profile "$p")
    if [[ ! " $steps_var " =~ " setup_gaming " ]]; then
        pass "Profile '$p' excludes setup_gaming"
    else
        fail "Profile '$p' should NOT include setup_gaming"
    fi
done

p="full"
steps_var=$(get_steps_for_profile "$p")
if [[ " $steps_var " =~ " setup_gaming " ]]; then
    pass "Profile '$p' includes setup_gaming"
else
    fail "Profile '$p' missing setup_gaming"
fi

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
        prompt_input() { echo "${2:-}"; }
        HAS_NVIDIA=false
        HAS_AMD=false
        HAS_INTEL=false
        IS_LAPTOP=false

        run_sudo() {
            if [[ "$1" == "dnf" && "$2" == "install" ]]; then
                shift 2
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        -y|--skip-unavailable) shift ;;
                        /tmp/vesktop.rpm) touch "$sandbox/.vesktop_installed"; shift ;;
                        steam-devices) touch "$sandbox/.steam_unlocked"; echo -n "$1 " >> "$sandbox/.dnf_pkgs"; shift ;;
                        *) echo -n "$1 " >> "$sandbox/.dnf_pkgs"; shift ;;
                    esac
                done
                return 0
            elif [[ "$1" == "dnf" && ( "$2" == "remove" || "$2" == "config-manager" || "$2" == "copr" ) ]]; then
                return 0
            fi
            "$@"
        }

        run() {
            "$@"
        }

        # Mock flatpak & steam & xdg-open & sleep
        flatpak() {
            if [[ "$1" == "install" && "$*" == *"com.heroicgameslauncher.hgl"* ]]; then
                touch "$sandbox/.heroic_installed"
                return 0
            fi
            return 1
        }
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
            elif [[ "$1" == "-v" && "$2" == "heroic" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        rpm() { return 1; }
        curl() {
            local prev=""
            for arg in "$@"; do
                if [[ "$prev" == "-o" ]]; then
                    mkdir -p "$(dirname "$arg")" 2>/dev/null || true
                    touch "$arg" 2>/dev/null || true
                    return 0
                fi
                prev="$arg"
            done
            return 0
        }
        git() { return 0; }
        lspci() { return 0; }
        github_download() {
            touch "$3"
            return 0
        }
        sleep() { command sleep 0.05; }

        SYS_ARCH="$(uname -m)"
        DEV_TYPE="all"

        # Extract profile helpers and domain step definitions from setup.sh
        eval "$(sed -n "/is_gaming_profile() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/is_creator_profile() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/is_dev_profile() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/setup_cli_core() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/setup_desktop_apps() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/setup_gaming() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/setup_creator() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/setup_dev() {/,/^}/p" "$setup_script")"

        # Execute domain steps according to profile
        setup_cli_core
        if [[ "$PROFILE" != "minimal" ]]; then
            setup_desktop_apps
        fi
        if [[ "$PROFILE" == "gaming" || "$PROFILE" == "full" ]]; then
            setup_gaming
        fi
        if [[ "$PROFILE" == "creator" || "$PROFILE" == "full" ]]; then
            setup_creator
        fi
        if [[ "$PROFILE" == "dev" || "$PROFILE" == "full" ]]; then
            setup_dev
        fi

        # Output state
        echo -n "DNF_PKGS:"
        [[ -f "$sandbox/.dnf_pkgs" ]] && cat "$sandbox/.dnf_pkgs"
        echo ""
        echo "STEAM_UNLOCKED:$([[ -f "$sandbox/.steam_unlocked" ]] && echo true || echo false)"
        echo "MANGOHUD_CONFIGURED:$([[ -f "$sandbox/.config/MangoHud/MangoHud.conf" ]] && echo true || echo false)"
        echo "VESKTOP_INSTALLED:$([[ -f "$sandbox/.vesktop_installed" ]] && echo true || echo false)"
        echo "HEROIC_INSTALLED:$([[ -f "$sandbox/.heroic_installed" ]] && echo true || echo false)"
        echo "HEROIC_PREFIX_CREATED:$([[ -d "$sandbox/Games/Heroic/Prefixes/shared" ]] && echo true || echo false)"
    ' _ "$target_profile" "$sandbox" "$SETUP_SCRIPT"

    rm -rf "$sandbox"
}

# Test gaming packages in gaming and full profiles
for prof in "gaming" "full"; do
    output=$(run_mock_setup_packages "$prof")
    dnf_pkgs=$(echo "$output" | grep "^DNF_PKGS:" | cut -d: -f2-)
    steam_unlocked=$(echo "$output" | grep "^STEAM_UNLOCKED:" | cut -d: -f2)
    mangohud_conf=$(echo "$output" | grep "^MANGOHUD_CONFIGURED:" | cut -d: -f2)
    vesktop_inst=$(echo "$output" | grep "^VESKTOP_INSTALLED:" | cut -d: -f2)

    # 1. steam, mangohud, gamemode in DNF
    if [[ " $dnf_pkgs " =~ " steam " && " $dnf_pkgs " =~ " mangohud " && " $dnf_pkgs " =~ " gamemode " ]]; then
        pass "Profile '$prof': steam, mangohud, and gamemode included in DNF packages"
    else
        fail "Profile '$prof': steam, mangohud, or gamemode missing from DNF packages (got: $dnf_pkgs)"
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

    # 6. Heroic Games Launcher installation & prefix setup
    heroic_inst=$(echo "$output" | grep "^HEROIC_INSTALLED:" | cut -d: -f2)
    heroic_prefix=$(echo "$output" | grep "^HEROIC_PREFIX_CREATED:" | cut -d: -f2)
    if [[ "$heroic_inst" == "true" ]]; then
        pass "Profile '$prof': Heroic Games Launcher Flatpak install executed"
    else
        fail "Profile '$prof': Heroic Games Launcher was NOT installed"
    fi
    if [[ "$heroic_prefix" == "true" ]]; then
        pass "Profile '$prof': Heroic prefix directory initialized"
    else
        fail "Profile '$prof': Heroic prefix directory was NOT initialized"
    fi
done

# Test workstation and creator profiles (must NOT include steam/mangohud/gamemode or their configs, but MUST include eza and vesktop)
for non_game_prof in "workstation" "creator"; do
    output=$(run_mock_setup_packages "$non_game_prof")
    dnf_pkgs=$(echo "$output" | grep "^DNF_PKGS:" | cut -d: -f2-)
    steam_unlocked=$(echo "$output" | grep "^STEAM_UNLOCKED:" | cut -d: -f2)
    mangohud_conf=$(echo "$output" | grep "^MANGOHUD_CONFIGURED:" | cut -d: -f2)
    vesktop_inst=$(echo "$output" | grep "^VESKTOP_INSTALLED:" | cut -d: -f2)

    if [[ ! " $dnf_pkgs " =~ " steam " && ! " $dnf_pkgs " =~ " mangohud " && ! " $dnf_pkgs " =~ " gamemode " ]]; then
        pass "Profile '$non_game_prof': steam, mangohud, and gamemode are excluded from DNF packages"
    else
        fail "Profile '$non_game_prof': gaming packages unexpectedly present in DNF packages (got: $dnf_pkgs)"
    fi

    if [[ " $dnf_pkgs " =~ " eza " ]]; then
        pass "Profile '$non_game_prof': eza included in DNF packages"
    else
        fail "Profile '$non_game_prof': eza missing from DNF packages"
    fi

    if [[ "$steam_unlocked" == "false" ]]; then
        pass "Profile '$non_game_prof': Steam H264 codec unlock is NOT executed"
    else
        fail "Profile '$non_game_prof': Steam H264 codec unlock should NOT be executed"
    fi

    if [[ "$mangohud_conf" == "false" ]]; then
        pass "Profile '$non_game_prof': MangoHud config is NOT created"
    else
        fail "Profile '$non_game_prof': MangoHud config should NOT be created"
    fi

    if [[ "$vesktop_inst" == "true" ]]; then
        pass "Profile '$non_game_prof': Vesktop RPM download & install executed"
    else
        fail "Profile '$non_game_prof': Vesktop was NOT installed"
    fi

    non_heroic_inst=$(echo "$output" | grep "^HEROIC_INSTALLED:" | cut -d: -f2)
    if [[ "$non_heroic_inst" == "false" ]]; then
        pass "Profile '$non_game_prof': Heroic Games Launcher is NOT installed"
    else
        fail "Profile '$non_game_prof': Heroic Games Launcher should NOT be installed"
    fi
done

# Test creator packages (akmod-v4l2loopback) in creator and full vs gaming, workstation
for c_prof in "creator" "full"; do
    output=$(run_mock_setup_packages "$c_prof")
    dnf_pkgs=$(echo "$output" | grep "^DNF_PKGS:" | cut -d: -f2-)
    if [[ " $dnf_pkgs " =~ " akmod-v4l2loopback " ]]; then
        pass "Profile '$c_prof': akmod-v4l2loopback included in DNF packages"
    else
        fail "Profile '$c_prof': akmod-v4l2loopback missing from DNF packages"
    fi
done

for non_c_prof in "gaming" "workstation" "dev"; do
    output=$(run_mock_setup_packages "$non_c_prof")
    dnf_pkgs=$(echo "$output" | grep "^DNF_PKGS:" | cut -d: -f2-)
    if [[ ! " $dnf_pkgs " =~ " akmod-v4l2loopback " ]]; then
        pass "Profile '$non_c_prof': akmod-v4l2loopback excluded from DNF packages"
    else
        fail "Profile '$non_c_prof': akmod-v4l2loopback should NOT be installed"
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

dev_heroic_inst=$(echo "$dev_output" | grep "^HEROIC_INSTALLED:" | cut -d: -f2)
if [[ "$dev_heroic_inst" == "false" ]]; then
    pass "Profile 'dev': Heroic Games Launcher is NOT installed"
else
    fail "Profile 'dev': Heroic Games Launcher should NOT be installed in dev profile"
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
        prompt_input() { echo "${2:-}"; }
        github_download() { touch "$3"; return 0; }
        HAS_NVIDIA=false
        HAS_AMD=false
        HAS_INTEL=false
        IS_LAPTOP=false

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

        # Extract domain functions with COPR from setup.sh
        eval "$(sed -n "/setup_desktop_apps() {/,/^}/p" "$setup_script")"
        eval "$(sed -n "/setup_dev() {/,/^}/p" "$setup_script")"

        SYS_ARCH="$(uname -m)"
        DEV_TYPE="android"
        PROFILE="full"
        setup_desktop_apps
        setup_dev

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
        eval "$(sed -n "/setup_gaming() {/,/^}/p" "$setup_script")"
        setup_gaming
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

if echo "$dry_output" | grep -q "Install Heroic Games Launcher Flatpak"; then
    pass "Dry-run gaming profile logs Heroic Games Launcher Flatpak action"
else
    fail "Dry-run gaming profile missing Heroic Flatpak log"
fi

dry_dev_output=$(bash "$SETUP_SCRIPT" --dry-run -f --profile=dev 2>&1)
if ! echo "$dry_dev_output" | grep -q "Unlock Steam H264 codec" && \
   ! echo "$dry_dev_output" | grep -q "Create MangoHud.conf" && \
   ! echo "$dry_dev_output" | grep -q "Heroic Games Launcher"; then
    pass "Dry-run dev profile does NOT log gaming actions or Heroic Games Launcher"
else
    fail "Dry-run dev profile unexpectedly logged gaming actions or Heroic"
fi

if echo "$dry_dev_output" | grep -q "Download and install Vesktop RPM"; then
    pass "Dry-run dev profile logs Vesktop RPM download action"
else
    fail "Dry-run dev profile missing Vesktop download log"
fi

# ==============================================================================
# Suite 8: GPU Terminal Emulator Selection & Configuration
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 8: GPU Terminal Emulator Selection & Configuration ---${NC}"

# 8.1: Test setup_packages does NOT unconditionally include kitty, ghostty, or alacritty
if grep -A 10 "setup_packages()" "$SETUP_SCRIPT" | grep -w "pkgs_to_install" | grep -qE "kitty|ghostty|alacritty"; then
    fail "Terminal emulator found in unconditional setup_packages() list"
else
    pass "Terminal emulators are NOT unconditionally included in setup_packages() DNF list"
fi

# 8.2: Test setup_shell gates setup_terminal strictly on is_dev_profile
if grep -A 3 "Terminal emulator configuration" "$SETUP_SCRIPT" | grep -q "is_dev_profile"; then
    pass "setup_shell gates setup_terminal strictly on is_dev_profile"
else
    fail "setup_shell does not gate setup_terminal on is_dev_profile"
fi

# 8.3: Test setup_terminal prompts user for modern terminal emulator with Ghostty recommended
if grep -q 'Prompt user for Terminal Emulator selection: \[1\] Ghostty (Recommended), \[2\] Kitty, \[3\] Alacritty' "$SETUP_SCRIPT"; then
    pass "setup_terminal prompts user with Ghostty (Recommended), Kitty, and Alacritty options"
else
    fail "setup_terminal missing expected multi-choice terminal prompt"
fi

# 8.4: Test dry-run dev profile logs terminal emulator selection and Ghostty Copr enable
if echo "$dry_dev_output" | grep -q "Prompt user for Terminal Emulator selection: \[1\] Ghostty (Recommended)"; then
    pass "Dry-run dev profile logs terminal emulator selection"
else
    fail "Dry-run dev profile missing terminal emulator selection log"
fi

if echo "$dry_dev_output" | grep -q "Enable Copr repo scottames/ghostty and install ghostty via dnf"; then
    pass "Dry-run dev profile logs Ghostty Copr installation (default choice)"
else
    fail "Dry-run dev profile missing Ghostty Copr installation log"
fi

# 8.5: Test dry-run gaming profile does NOT prompt for terminal emulator
if ! echo "$dry_output" | grep -q "Configuring Terminal Emulator"; then
    pass "Dry-run gaming profile does NOT prompt for terminal emulator (preserves stock Ptyxis)"
fi

# ==============================================================================
# Suite 9: AOSP/Multilib Removal & dpkg-dev Profile Isolation
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 9: AOSP/Multilib Removal & dpkg-dev Profile Isolation ---${NC}"

# 9.1: Verify android-tools is included in setup_cli_core for phone connectivity/debugging
pkgs_to_install_array=$(sed -n '/setup_cli_core()/,/^}/p' "$SETUP_SCRIPT" | sed -n '/local cli_pkgs=(/,/)/p')
if echo "$pkgs_to_install_array" | grep -q "android-tools"; then
    pass "android-tools is included in setup_cli_core() for Android device connectivity"
else
    fail "android-tools missing from setup_cli_core()"
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

# 9.4: Verify full profile only dev packages (dpkg-dev, copr-cli, osc, python3-keyring, GUI/audio development libraries)
dev_pkgs_array=$(sed -n '/setup_dev()/,/^}/p' "$SETUP_SCRIPT" | sed -n '/local dev_pkgs=(/,/)/p')
for full_only_pkg in "dpkg-dev" "copr-cli" "osc" "python3-keyring" "libX11-devel" "libxkbcommon-x11-devel" "libxcb-devel" "fontconfig-devel" "alsa-lib-devel"; do
    if echo "$dev_pkgs_array" | grep -q "$full_only_pkg"; then
        fail "$full_only_pkg is unconditionally present in dev_pkgs"
    else
        pass "$full_only_pkg is not in unconditional dev_pkgs array"
    fi

    if grep -A 15 '\[\[ "\$PROFILE" == "full" \]\]' "$SETUP_SCRIPT" | grep -q "$full_only_pkg"; then
        pass "$full_only_pkg is strictly gated on PROFILE=full"
    else
        fail "$full_only_pkg is missing full profile gate in setup_dev"
    fi
done

# ==============================================================================
# Suite 10: Profile Cleanliness & Decoupling (No Personal Profile Quirks)
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 10: Profile Cleanliness & Decoupling ---${NC}"

# 10.1: Verify setup_packages does not contain personal profile gate
if ! sed -n '/setup_packages()/,/^}/p' "$SETUP_SCRIPT" | grep -q '\[\[ "$PROFILE" == "personal" \]\]'; then
    pass "setup_packages() contains no personal profile gate"
else
    fail "setup_packages() still contains personal profile gate"
fi

# 10.2: Verify setup_packages does not contain cliamp
setup_pkg_body=$(sed -n '/setup_packages()/,/^}/p' "$SETUP_SCRIPT")
if ! echo "$setup_pkg_body" | grep -q "cliamp"; then
    pass "setup_packages() excludes cliamp"
else
    fail "setup_packages() unexpectedly contains cliamp"
fi

# 10.3: Verify setup_packages does not contain ani-cli
if ! echo "$setup_pkg_body" | grep -q "ani-cli"; then
    pass "setup_packages() excludes ani-cli"
else
    fail "setup_packages() unexpectedly contains ani-cli"
fi

# 10.4: Verify setup_packages does not contain ONLYOFFICE swap
if ! echo "$setup_pkg_body" | grep -q "onlyoffice-desktopeditors"; then
    pass "setup_packages() excludes ONLYOFFICE Desktop Editors"
else
    fail "setup_packages() unexpectedly contains ONLYOFFICE Desktop Editors"
fi

# 10.5: Verify setup_copr does not contain kkfetch
if ! sed -n '/setup_copr()/,/^}/p' "$SETUP_SCRIPT" | grep -q "kkfetch"; then
    pass "setup_copr() excludes kkfetch"
else
    fail "setup_copr() unexpectedly contains kkfetch"
fi

# 10.6: Verify setup_shell does not contain kkfetch
if ! sed -n '/setup_shell()/,/^}/p' "$SETUP_SCRIPT" | grep -q "kkfetch"; then
    pass "setup_shell() excludes kkfetch"
else
    fail "setup_shell() unexpectedly contains kkfetch"
fi

# ==============================================================================
# Suite 11: Shell Selection & Environment Isolation
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 11: Shell Selection & Environment Isolation ---${NC}"

# 11.1: Verify setup_shell gates interactive shell selection to dev and full profiles
if grep -B 5 -A 5 'Default Interactive Shell:' "$SETUP_SCRIPT" | grep -q 'PROFILE" == "dev" || "$PROFILE" == "full"'; then
    pass "setup_shell gates interactive shell menu strictly to dev and full profiles"
else
    fail "setup_shell does not gate interactive shell menu to dev and full profiles"
fi

# 11.2: Verify setup_shell gates dev exports/aliases menu to dev and full profiles
if grep -A 5 'Developer Environment & Aliases Configuration' "$SETUP_SCRIPT" | grep -q 'dev_env_choice'; then
    pass "setup_shell presents developer environment and aliases configuration menu"
else
    fail "setup_shell missing developer environment menu"
fi

# 11.3: Verify dry-run dev profile logs default shell selection and dev aliases prompt
if echo "$dry_dev_output" | grep -q "Prompt user for default shell selection: \[1\] Fish (Recommended)" && \
   echo "$dry_dev_output" | grep -q "Prompt for developer environment & aliases configuration for Fish"; then
    pass "Dry-run dev profile logs shell selection and dev environment prompts"
else
    fail "Dry-run dev profile missing shell selection or dev environment prompt logs"
fi

# 11.4: Verify dry-run gaming profile bypasses shell prompts and deploys clean standard aliases
if ! echo "$dry_output" | grep -q "Prompt user for default shell selection" && \
   ! echo "$dry_output" | grep -q "Prompt for developer environment & aliases configuration" && \
   echo "$dry_output" | grep -q "Deploy Fish clean standard aliases" && \
   echo "$dry_output" | grep -q "Deploy ZSH clean standard aliases" && \
   echo "$dry_output" | grep -q "Deploy Bash clean standard aliases"; then
    pass "Dry-run gaming profile deploys clean standard aliases without shell prompts"
else
    fail "Dry-run gaming profile unexpectedly prompted for shell selection or missed clean standard aliases"
fi

# 11.5: Verify setup_shell contains the 4 exact clean standard aliases
if grep -q "alias clear 'printf \"\\\033\[2J\\\033\[3J\\\033\[H\"'" "$SETUP_SCRIPT" && \
   grep -q "alias ls 'eza --group-directories-first --classify --icons --git'" "$SETUP_SCRIPT" && \
   grep -q "alias cat 'bat --paging=never --style=plain'" "$SETUP_SCRIPT" && \
   grep -q "alias less 'bat --paging=always --pager=\"less -R\"'" "$SETUP_SCRIPT"; then
    pass "setup_shell defines exact clean standard aliases (clear, ls, cat, less)"
else
    fail "setup_shell missing expected clean standard aliases"
fi

# 11.6: Verify setup_shell gates Starship confirmation prompt strictly to dev and full profiles
if grep -B 5 -A 5 'Starship Cross-Shell Prompt:' "$SETUP_SCRIPT" | grep -q 'PROFILE" == "dev" || "$PROFILE" == "full"'; then
    pass "setup_shell gates Starship prompt strictly to dev and full profiles"
else
    fail "setup_shell does not gate Starship prompt to dev and full profiles"
fi

# 11.7: Verify dry-run dev profile logs Starship prompt and config deployment
if echo "$dry_dev_output" | grep -q "Prompt: Install and configure Starship prompt?" && \
   echo "$dry_dev_output" | grep -q "Deploy Starship prompt configuration to ~/.config/starship.toml"; then
    pass "Dry-run dev profile prompts for Starship and logs configuration deployment"
else
    fail "Dry-run dev profile missing Starship prompt or configuration deployment log"
fi

# 11.8: Verify dry-run gaming profile bypasses Starship prompt and does NOT deploy starship.toml
if ! echo "$dry_output" | grep -q "Prompt: Install and configure Starship prompt?" && \
   ! echo "$dry_output" | grep -q "Deploy Starship prompt configuration to ~/.config/starship.toml"; then
    pass "Dry-run gaming profile completely bypasses Starship prompt and configuration deployment"
else
    fail "Dry-run gaming profile unexpectedly prompted for Starship or deployed starship.toml"
fi

# ==============================================================================
# Suite 12: ccache Compiler Cache Configuration & Genre Gating
# ==============================================================================
echo ""
echo -e "${BLUE}--- Suite 12: ccache Compiler Cache Configuration & Genre Gating ---${NC}"

# 12.1: Verify setup_dev gates ccache prompt on has_dev_genre "systems"
if grep -B 10 -A 10 'ccache (Fast C/C++ Compiler Cache):' "$SETUP_SCRIPT" | grep -q 'has_dev_genre "systems"'; then
    pass "setup_dev gates ccache prompt strictly on systems dev genre"
else
    fail "setup_dev does not gate ccache prompt on systems dev genre"
fi

# 12.2: Verify dry-run dev profile (all genres) prompts for ccache and installs/configures it
if echo "$dry_dev_output" | grep -q "Prompt: Install and configure ccache" && \
   echo "$dry_dev_output" | grep -q "sudo dnf install -y --skip-unavailable ccache" && \
   echo "$dry_dev_output" | grep -q "Configure ccache: 50GB max size, compression enabled"; then
    pass "Dry-run dev profile prompts for ccache and logs installation & configuration"
else
    fail "Dry-run dev profile missing ccache prompt or configuration logs"
fi

# 12.4: Verify dry-run gaming profile does not prompt for or configure ccache
if ! echo "$dry_output" | grep -q "Prompt: Install and configure ccache" && \
   ! echo "$dry_output" | grep -q "Configure ccache:"; then
    pass "Dry-run gaming profile completely bypasses ccache"
else
    fail "Dry-run gaming profile unexpectedly prompted for or configured ccache"
fi

echo ""
echo "================================================================"
echo "SUMMARY: Total Tests: $TOTAL, Passed: $PASSED, Failed: $FAILED"
echo "================================================================"

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
