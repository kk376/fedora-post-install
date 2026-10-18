#!/bin/bash
set -euo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/setup.sh"
FAILED=0
PASSED=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  [PASS] $label"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $label"
        echo "         Expected: $expected"
        echo "         Actual:   $actual"
        FAILED=$((FAILED + 1))
    fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ " $haystack " == *" $needle "* ]]; then
        echo "  [PASS] $label"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $label: expected '$haystack' to contain '$needle'"
        FAILED=$((FAILED + 1))
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ " $haystack " != *" $needle "* ]]; then
        echo "  [PASS] $label"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $label: expected '$haystack' NOT to contain '$needle'"
        FAILED=$((FAILED + 1))
    fi
}

# Extract and evaluate step lists directly from setup.sh by parsing main()
get_profile_steps() {
    local target_profile="$1"
    bash -c "
        info() { :; }
        log() { :; }
        warn() { :; }
        error() { :; }
        init_state() { :; }
        confirm() { return 1; }

        code=\$(sed -n '/local steps=(/,/TOTAL_STEPS=/p' \"$SCRIPT_PATH\")
        code=\$(echo \"\$code\" | sed 's/local -A /declare -g -A /g; s/local /declare -g /g')
        PROFILE=\"$target_profile\"
        eval \"\$code\"

        filtered_steps=()
        for step in \"\${steps[@]}\"; do
            IFS=':' read -r func _ <<< \"\$step\"
            if [[ -z \"\${PROFILE_STEPS[\$PROFILE]}\" ]] || [[ \" \${PROFILE_STEPS[\$PROFILE]} \" =~ \" \$func \" ]]; then
                filtered_steps+=(\"\$func\")
            fi
        done
        echo \"\${filtered_steps[*]}\"
    "
}

echo "================================================================"
echo "TEST SUITE: Profile Integrity & Execution Order (v7.0.0)"
echo "Target Script: $SCRIPT_PATH"
echo "================================================================"

declare -A EXPECTED_STEPS
EXPECTED_STEPS[minimal]="setup_dnf setup_dns setup_cli_core setup_shell"
EXPECTED_STEPS[workstation]="setup_dnf setup_dns setup_cli_core setup_shell setup_fonts setup_multimedia setup_gnome setup_desktop_apps setup_power setup_pre_driver_reboot setup_drivers"
EXPECTED_STEPS[dev]="setup_dnf setup_dns setup_cli_core setup_shell setup_fonts setup_multimedia setup_gnome setup_desktop_apps setup_power setup_dev setup_editor setup_docker setup_kvm setup_pre_driver_reboot setup_drivers"
EXPECTED_STEPS[gaming]="setup_dnf setup_dns setup_cli_core setup_shell setup_fonts setup_multimedia setup_gnome setup_desktop_apps setup_power setup_gaming setup_pre_driver_reboot setup_drivers"
EXPECTED_STEPS[creator]="setup_dnf setup_dns setup_cli_core setup_shell setup_fonts setup_multimedia setup_gnome setup_desktop_apps setup_power setup_creator setup_pre_driver_reboot setup_drivers"
EXPECTED_STEPS[full]="setup_dnf setup_dns setup_cli_core setup_shell setup_fonts setup_multimedia setup_gnome setup_desktop_apps setup_power setup_dev setup_editor setup_docker setup_kvm setup_gaming setup_creator setup_pre_driver_reboot setup_drivers"

declare -A EXPECTED_NAMES
EXPECTED_NAMES[minimal]="DNF5 & Repositories, DNS Resolvers, Core CLI Utilities, Shell & Terminal"
EXPECTED_NAMES[workstation]="DNF5 & Repositories, DNS Resolvers, Core CLI Utilities, Shell & Terminal, System & Nerd Fonts, Multimedia & Audio Codecs, GNOME Desktop & Extensions, Desktop Applications, Power & Sleep Management, Pre-Driver Kernel Checkpoint, GPU Drivers"
EXPECTED_NAMES[dev]="DNF5 & Repositories, DNS Resolvers, Core CLI Utilities, Shell & Terminal, System & Nerd Fonts, Multimedia & Audio Codecs, GNOME Desktop & Extensions, Desktop Applications, Power & Sleep Management, Development Toolchains, Code Editor, Docker & Compose, KVM/QEMU Virtualization, Pre-Driver Kernel Checkpoint, GPU Drivers"
EXPECTED_NAMES[gaming]="DNF5 & Repositories, DNS Resolvers, Core CLI Utilities, Shell & Terminal, System & Nerd Fonts, Multimedia & Audio Codecs, GNOME Desktop & Extensions, Desktop Applications, Power & Sleep Management, Gaming Stack, Pre-Driver Kernel Checkpoint, GPU Drivers"
EXPECTED_NAMES[creator]="DNF5 & Repositories, DNS Resolvers, Core CLI Utilities, Shell & Terminal, System & Nerd Fonts, Multimedia & Audio Codecs, GNOME Desktop & Extensions, Desktop Applications, Power & Sleep Management, Creator & Streaming Suite, Pre-Driver Kernel Checkpoint, GPU Drivers"
EXPECTED_NAMES[full]="DNF5 & Repositories, DNS Resolvers, Core CLI Utilities, Shell & Terminal, System & Nerd Fonts, Multimedia & Audio Codecs, GNOME Desktop & Extensions, Desktop Applications, Power & Sleep Management, Development Toolchains, Code Editor, Docker & Compose, KVM/QEMU Virtualization, Gaming Stack, Creator & Streaming Suite, Pre-Driver Kernel Checkpoint, GPU Drivers"

declare -A EXPECTED_COUNTS
EXPECTED_COUNTS[minimal]=4
EXPECTED_COUNTS[workstation]=11
EXPECTED_COUNTS[dev]=15
EXPECTED_COUNTS[gaming]=12
EXPECTED_COUNTS[creator]=12
EXPECTED_COUNTS[full]=17

ALL_PROFILES=("minimal" "workstation" "dev" "gaming" "creator" "full")

# 1. Verify Step Lists and Step Counts for all 6 profiles
echo ""
echo "--- 1. Testing Step Lists and Counts for All Profiles ---"
for p in "${ALL_PROFILES[@]}"; do
    actual_steps=$(get_profile_steps "$p")
    actual_count=$(wc -w <<< "$actual_steps")
    
    assert_eq "Profile '$p' step count" "${EXPECTED_COUNTS[$p]}" "$actual_count"
    assert_eq "Profile '$p' exact step sequence" "${EXPECTED_STEPS[$p]}" "$actual_steps"
done

# 2. Verify Driver Steps Order Across Workstation Profiles
echo ""
echo "--- 2. Testing Driver Steps Order Across Workstation Profiles ---"
WORKSTATION_PROFILES=("workstation" "dev" "gaming" "creator" "full")
for p in "${WORKSTATION_PROFILES[@]}"; do
    actual_steps=$(get_profile_steps "$p")
    read -r -a steps_arr <<< "$actual_steps"
    total=${#steps_arr[@]}
    
    second_to_last="${steps_arr[$((total - 2))]}"
    last="${steps_arr[$((total - 1))]}"
    
    assert_eq "Profile '$p' second-to-last step is setup_pre_driver_reboot" "setup_pre_driver_reboot" "$second_to_last"
    assert_eq "Profile '$p' last step is setup_drivers" "setup_drivers" "$last"
    assert_contains "Profile '$p' contains setup_pre_driver_reboot" "setup_pre_driver_reboot" "$actual_steps"
    assert_contains "Profile '$p' contains setup_drivers" "setup_drivers" "$actual_steps"
done

# Minimal profile is CLI-only and excludes driver steps
assert_not_contains "Profile 'minimal' excludes setup_pre_driver_reboot" "setup_pre_driver_reboot" "$(get_profile_steps minimal)"
assert_not_contains "Profile 'minimal' excludes setup_drivers" "setup_drivers" "$(get_profile_steps minimal)"

# 3. Verify End-to-End Dry-Run Execution Trace
echo ""
echo "--- 3. Testing End-to-End Runtime Execution Order via Dry Run ---"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

for p in "${ALL_PROFILES[@]}"; do
    # Run setup.sh with force and capture runtime steps
    raw_output=$(bash "$SCRIPT_PATH" --dry-run --force --profile="$p" <<< "N" 2>&1)
    
    clean_output=$(echo "$raw_output" | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g')
    runtime_steps=$(echo "$clean_output" | grep '^Step: ' | sed 's/Step: //' | paste -sd ',' - | sed 's/,/, /g')
    
    assert_eq "Profile '$p' runtime execution order" "${EXPECTED_NAMES[$p]}" "$runtime_steps"
done

# 4. Verify CLI Profile Flag Handling & Validation
echo ""
echo "--- 4. Testing CLI Profile Flag Handling & Validation ---"

for p in "${ALL_PROFILES[@]}"; do
    if bash "$SCRIPT_PATH" --dry-run --profile="$p" <<< "N" &>/dev/null; then
        echo "  [PASS] CLI handles --profile=$p"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] CLI failed with --profile=$p"
        FAILED=$((FAILED + 1))
    fi
    if bash "$SCRIPT_PATH" --dry-run --profile "$p" <<< "N" &>/dev/null; then
        echo "  [PASS] CLI handles --profile $p (separate argument)"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] CLI failed with --profile $p"
        FAILED=$((FAILED + 1))
    fi
done

# Test CLI validation for invalid profile
if bash "$SCRIPT_PATH" --profile=invalid_profile &>/dev/null; then
    echo "  [FAIL] CLI accepted invalid profile"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] CLI rejected invalid profile"
    PASSED=$((PASSED + 1))
fi

echo ""
echo "================================================================"
echo "SUMMARY: Total Passed: $PASSED, Total Failed: $FAILED"
echo "================================================================"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
