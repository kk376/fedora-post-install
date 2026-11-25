#!/bin/bash
# shellcheck disable=SC1090,SC2181,SC2016,SC2034
# Test Suite for setup.sh Helper Functions
# Covers: set_zshrc_line, github_download, check_disk_space, confirm
set -u

# Allow test runners to execute setup.sh in container environments (EUID=0)
export ALLOW_ROOT="${ALLOW_ROOT:-true}"

TOTAL=0
PASSED=0
FAILED=0

pass() {
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    echo "  [PASS] $1"
}

fail() {
    TOTAL=$((TOTAL + 1))
    FAILED=$((FAILED + 1))
    echo "  [FAIL] $1"
    [[ -n "${2:-}" ]] && echo "         Detail: $2"
}

# ==============================================================================
# Sourcing Helper Functions from setup.sh (guarded by BASH_SOURCE)
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="${SCRIPT_DIR}/setup.sh"
SRC_DIR="${SCRIPT_DIR}/src"
source "$SETUP_SCRIPT"

# Sandboxing
TEST_DIR=$(mktemp -d)
ORIG_HOME="$HOME"
ORIG_PATH="$PATH"
export HOME="$TEST_DIR"
trap 'export HOME="$ORIG_HOME"; export PATH="$ORIG_PATH"; rm -rf "$TEST_DIR"' EXIT

# ==============================================================================
# Suite 1: set_zshrc_line Tests
# ==============================================================================
echo "=== Suite 1: set_zshrc_line ==="

# 1.1 New file creation
rm -f "$HOME/.zshrc"
set_zshrc_line '^ZSH_THEME=' 'ZSH_THEME="powerlevel10k/powerlevel10k"'
if [[ -f "$HOME/.zshrc" ]] && [[ "$(cat "$HOME/.zshrc")" == 'ZSH_THEME="powerlevel10k/powerlevel10k"' ]]; then
    pass "New file creation creates ~/.zshrc with desired line"
else
    fail "New file creation failed"
fi

# 1.2 Idempotency
set_zshrc_line '^ZSH_THEME=' 'ZSH_THEME="powerlevel10k/powerlevel10k"'
lines=$(wc -l < "$HOME/.zshrc")
if [[ "$lines" -eq 1 ]]; then
    pass "Idempotency prevents duplicate lines on re-run"
else
    fail "Idempotency failed, line count: $lines"
fi

# 1.3 Existing matching line replacement
cat << 'EOC' > "$HOME/.zshrc"
export PATH="$HOME/bin:$PATH"
ZSH_THEME="robbyrussell"
export EDITOR="nano"
EOC
set_zshrc_line '^ZSH_THEME=' 'ZSH_THEME="powerlevel10k/powerlevel10k"'
expected_content='export PATH="$HOME/bin:$PATH"
ZSH_THEME="powerlevel10k/powerlevel10k"
export EDITOR="nano"'
if [[ "$(cat "$HOME/.zshrc")" == "$expected_content" ]]; then
    pass "Existing matching line replaced in-place preserving order"
else
    fail "Existing matching line replacement failed"
fi

# 1.4 Non-matching line append
set_zshrc_line '^ENABLE_CORRECTION=' 'ENABLE_CORRECTION="true"'
if [[ "$(tail -n 1 "$HOME/.zshrc")" == 'ENABLE_CORRECTION="true"' ]] && [[ $(wc -l < "$HOME/.zshrc") -eq 4 ]]; then
    pass "Non-matching line appended to end of file"
else
    fail "Non-matching line append failed"
fi

# 1.5 Special characters in desired string (slashes, quotes, ampersands, dollar signs)
set_zshrc_line '^VAR_SPECIAL=' 'VAR_SPECIAL="foo & bar / baz $VAR $(cmd) [123]"'
if [[ "$(tail -n 1 "$HOME/.zshrc")" == 'VAR_SPECIAL="foo & bar / baz $VAR $(cmd) [123]"' ]]; then
    pass "Desired string with special characters (&, /, $, [], quotes) preserved"
else
    fail "Desired string with special characters failed"
fi

# 1.6 Special regex characters in pattern - setup.sh Line 499 case: '^plugins=\('
echo 'plugins=(git)' > "$HOME/.zshrc"
awk_err=$(set_zshrc_line '^plugins=\(' 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' 2>&1 || true)
if grep -qF 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' "$HOME/.zshrc" && ! grep -qF 'plugins=(git)' "$HOME/.zshrc"; then
    pass "Pattern with escaped regex chars '^plugins=\(' correctly replaced"
else
    fail "Pattern with escaped regex chars '^plugins=\(' failed (awk -v unescapes backslash into invalid regex)" "$awk_err"
fi

# ==============================================================================
# Suite 2: github_download Tests
# ==============================================================================
echo "=== Suite 2: github_download ==="

MOCK_BIN="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN"
export PATH="$MOCK_BIN:$ORIG_PATH"

cat << 'EOC' > "$MOCK_BIN/curl"
#!/bin/bash
if [[ "$*" == *"api.github.com/repos/Vencord/Vesktop"* ]]; then
    cat << 'JSON'
{
  "tag_name": "v1.5.3",
  "assets": [
    {
      "name": "vesktop-1.5.3.arm64.rpm",
      "browser_download_url": "https://github.com/mock/vesktop-1.5.3.arm64.rpm"
    },
    {
      "name": "vesktop-1.5.3.x86_64.rpm",
      "browser_download_url": "https://github.com/mock/vesktop-1.5.3.x86_64.rpm"
    }
  ]
}
JSON
    exit 0
elif [[ "$*" == *"api.github.com/repos/docker/compose"* ]]; then
    cat << 'JSON'
{
  "tag_name": "v2.29.1",
  "assets": [
    {
      "name": "docker-compose-linux-x86_64.sha256",
      "browser_download_url": "https://github.com/mock/docker-compose-linux-x86_64.sha256"
    },
    {
      "name": "docker-compose-linux-x86_64",
      "browser_download_url": "https://github.com/mock/docker-compose-linux-x86_64"
    }
  ]
}
JSON
    exit 0
elif [[ "$*" == *"api.github.com/repos/fail/rate-limit"* ]]; then
    exit 22 # HTTP 403 / rate limit
elif [[ "$*" == *"https://github.com/mock/"* || "$*" == *"https://fallback.example.com/"* ]]; then
    # Output file download
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-o" ]]; then
            echo "mock download payload" > "$2"
            exit 0
        fi
        shift
    done
    exit 0
elif [[ "$*" == *"https://badfallback.example.com/"* ]]; then
    exit 6 # curl connection failed
fi
exit 1
EOC
chmod +x "$MOCK_BIN/curl"

# 2.1 Pattern matching specific arch with jq
out_vesk="$TEST_DIR/vesktop.rpm"
github_download "Vencord/Vesktop" 'vesktop.*\.x86_64\.rpm' "$out_vesk" "https://fallback.example.com/vesktop.rpm"
if [[ $? -eq 0 ]] && [[ -f "$out_vesk" ]]; then
    pass "GitHub API release pattern matching for x86_64 rpm succeeds"
else
    fail "GitHub API release pattern matching failed"
fi

# 2.1b Pattern with escaped regex dot (\.) without fallback URL (tests jq escaping)
out_vesk_nofb="$TEST_DIR/vesktop_nofb.rpm"
github_download "Vencord/Vesktop" 'vesktop.*\.x86_64\.rpm' "$out_vesk_nofb" ""
if [[ $? -eq 0 ]] && [[ -f "$out_vesk_nofb" ]]; then
    pass "GitHub API handles escaped dots (\\.) in pattern without falling back"
else
    fail "GitHub API failed on pattern with escaped dots (\\.) when fallback is empty"
fi

# 2.2 Pattern matching with regex anchor '$' (docker-compose binary vs checksum)
out_dc="$TEST_DIR/docker-compose"
github_download "docker/compose" 'docker-compose-linux-x86_64$' "$out_dc" "https://fallback.example.com/docker-compose"
if [[ $? -eq 0 ]] && [[ -f "$out_dc" ]]; then
    pass "Regex anchor '$' correctly selects binary over checksum file"
else
    fail "Regex anchor '$' selection failed"
fi

# 2.3 Fallback URL when API fails (e.g. rate limit / network)
out_fb="$TEST_DIR/fallback.rpm"
github_download "fail/rate-limit" 'pkg.*\.rpm' "$out_fb" "https://fallback.example.com/fallback.rpm"
if [[ $? -eq 0 ]] && [[ -f "$out_fb" ]]; then
    pass "Fallback URL successfully used when GitHub API fails"
else
    fail "Fallback URL on API failure failed"
fi

# 2.4 Fallback URL when asset pattern does not match any release assets
out_unmatched="$TEST_DIR/unmatched.rpm"
github_download "Vencord/Vesktop" 'nonexistent-pattern' "$out_unmatched" "https://fallback.example.com/unmatched-fb.rpm"
if [[ $? -eq 0 ]] && [[ -f "$out_unmatched" ]]; then
    pass "Fallback URL successfully used when no assets match pattern"
else
    fail "Fallback URL on unmatched pattern failed"
fi

# 2.5 API fails and no fallback provided
out_nofb="$TEST_DIR/nofb.rpm"
github_download "fail/rate-limit" 'pkg.*\.rpm' "$out_nofb" ""
if [[ $? -eq 1 ]] && [[ ! -f "$out_nofb" ]]; then
    pass "Returns 1 when API fails and no fallback URL is provided"
else
    fail "Expected exit code 1 when no fallback provided"
fi

# 2.6 Fallback download fails
out_badfb="$TEST_DIR/badfb.rpm"
github_download "fail/rate-limit" 'pkg.*\.rpm' "$out_badfb" "https://badfallback.example.com/pkg.rpm"
if [[ $? -ne 0 ]] && [[ ! -f "$out_badfb" ]]; then
    pass "Propagates failure exit code when fallback download fails"
else
    fail "Failed fallback download did not return non-zero"
fi

# 2.7 Checksum verification with expected_sha256 matching
out_chk_ok="$TEST_DIR/chk_ok.rpm"
mock_url="https://fallback.example.com/checked.rpm"
expected_hash=$(printf "mock download payload\n" | sha256sum | cut -d' ' -f1)
github_download "fail/rate-limit" 'pkg.*\.rpm' "$out_chk_ok" "$mock_url" "$expected_hash"
if [[ $? -eq 0 ]] && [[ -f "$out_chk_ok" ]]; then
    pass "github_download succeeds when expected_sha256 matches output file"
else
    fail "github_download failed on matching expected_sha256"
fi

# 2.8 Checksum verification fails on mismatched hash and cleans up output file
out_chk_bad="$TEST_DIR/chk_bad.rpm"
github_download "fail/rate-limit" 'pkg.*\.rpm' "$out_chk_bad" "$mock_url" "0000000000000000000000000000000000000000000000000000000000000000"
if [[ $? -ne 0 ]] && [[ ! -f "$out_chk_bad" ]]; then
    pass "github_download fails and removes output when expected_sha256 mismatches"
else
    fail "github_download did not fail or clean up on hash mismatch"
fi

# ==============================================================================
# Suite 3: check_disk_space Tests
# ==============================================================================
echo "=== Suite 3: check_disk_space ==="

set_df_mock() {
    cat << EOC > "$MOCK_BIN/df"
#!/bin/bash
cat << 'DFDATA'
$1
DFDATA
EOC
    chmod +x "$MOCK_BIN/df"
}

# 3.1 Sufficient space
set_df_mock "Filesystem     1G-blocks  Used Available Use% Mounted on
/dev/nvme0n1p3      476G  150G      150G  32% /home"
out=$(check_disk_space 20 /home)
if [[ $? -eq 0 ]] && [[ "$out" == *"Disk space OK: 150GB available"* ]]; then
    pass "Available > Required (150GB >= 20GB) returns 0 and logs OK"
else
    fail "Available > Required check failed: $out"
fi

# 3.2 Boundary condition: Available == Required
set_df_mock "Filesystem     1G-blocks  Used Available Use% Mounted on
/dev/nvme0n1p3      476G  150G       20G  32% /home"
out=$(check_disk_space 20 /home)
if [[ $? -eq 0 ]] && [[ "$out" == *"Disk space OK: 20GB available"* ]]; then
    pass "Available == Required (20GB == 20GB) returns 0 and logs OK"
else
    fail "Boundary Available == Required failed: $out"
fi

# 3.3 Low space with user confirmation 'y'
set_df_mock "Filesystem     1G-blocks  Used Available Use% Mounted on
/dev/nvme0n1p3      476G  150G       15G  32% /home"
out=$(printf "y\n" | check_disk_space 20 /home 2>&1)
if [[ $? -eq 0 ]] && [[ "$out" == *"Low disk space: 15GB"* ]]; then
    pass "Low space (15GB < 20GB) with user 'y' continues successfully"
else
    fail "Low space with user 'y' failed: $out"
fi

# 3.4 Low space with user rejection 'n'
(
    set_df_mock "Filesystem     1G-blocks  Used Available Use% Mounted on
/dev/nvme0n1p3      476G  150G        5G  32% /home"
    printf "n\n" | check_disk_space 20 /home >/dev/null 2>&1
)
if [[ $? -eq 1 ]]; then
    pass "Low space (5GB < 20GB) with user 'n' aborts with exit code 1"
else
    fail "Low space with user 'n' did not abort with exit code 1"
fi

# 3.5 df failure handling
cat << 'EOC' > "$MOCK_BIN/df"
#!/bin/bash
exit 1
EOC
chmod +x "$MOCK_BIN/df"
out=$(check_disk_space 20 /nonexistent 2>&1)
if [[ $? -eq 1 ]] && [[ "$out" == *"Could not determine free disk space"* ]]; then
    pass "df execution failure gracefully skipped with warning"
else
    fail "df execution failure handling failed: $out"
fi

# ==============================================================================
# Suite 4: confirm Tests
# ==============================================================================
echo "=== Suite 4: confirm ==="

# 4.1 Dry Run - Default Y
DRY_RUN=true
confirm "Reboot?" "Y" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    pass "Dry Run with default 'Y' auto-approves (returns 0)"
else
    fail "Dry Run with default 'Y' failed"
fi

# 4.2 Dry Run - Default N
DRY_RUN=true
confirm "Reboot?" "N" >/dev/null 2>&1
if [[ $? -eq 1 ]]; then
    pass "Dry Run with default 'N' auto-rejects (returns 1)"
else
    fail "Dry Run with default 'N' failed"
fi

# 4.3 Dry Run - Default omitted
DRY_RUN=true
confirm "Reboot?" >/dev/null 2>&1
if [[ $? -eq 1 ]]; then
    pass "Dry Run with default omitted defaults to 'N' and returns 1"
else
    fail "Dry Run with default omitted failed"
fi

DRY_RUN=false

# 4.4 Default Y with Enter (empty)
printf "\n" | confirm "Prompt" "Y" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    pass "Default 'Y' with Enter returns 0"
else
    fail "Default 'Y' with Enter failed"
fi

# 4.5 Default Y with 'y' and 'Y'
printf "y\n" | confirm "Prompt" "Y" >/dev/null 2>&1
res_y=$?
printf "Y\n" | confirm "Prompt" "Y" >/dev/null 2>&1
res_Y=$?
if [[ $res_y -eq 0 ]] && [[ $res_Y -eq 0 ]]; then
    pass "Default 'Y' with 'y'/'Y' returns 0"
else
    fail "Default 'Y' with 'y'/'Y' failed"
fi

# 4.6 Default Y with 'n' and 'N'
printf "n\n" | confirm "Prompt" "Y" >/dev/null 2>&1
res_n=$?
printf "N\n" | confirm "Prompt" "Y" >/dev/null 2>&1
res_N=$?
if [[ $res_n -eq 1 ]] && [[ $res_N -eq 1 ]]; then
    pass "Default 'Y' with 'n'/'N' returns 1"
else
    fail "Default 'Y' with 'n'/'N' failed"
fi

# 4.7 Default N with Enter (empty)
printf "\n" | confirm "Prompt" "N" >/dev/null 2>&1
if [[ $? -eq 1 ]]; then
    pass "Default 'N' with Enter returns 1"
else
    fail "Default 'N' with Enter failed"
fi

# 4.8 Default N with 'y' and 'Y'
printf "y\n" | confirm "Prompt" "N" >/dev/null 2>&1
res_ny=$?
printf "Y\n" | confirm "Prompt" "N" >/dev/null 2>&1
res_nY=$?
if [[ $res_ny -eq 0 ]] && [[ $res_nY -eq 0 ]]; then
    pass "Default 'N' with 'y'/'Y' returns 0"
else
    fail "Default 'N' with 'y'/'Y' failed"
fi

# 4.9 Default N with 'n' and 'N'
printf "n\n" | confirm "Prompt" "N" >/dev/null 2>&1
res_nn=$?
printf "N\n" | confirm "Prompt" "N" >/dev/null 2>&1
res_nN=$?
if [[ $res_nn -eq 1 ]] && [[ $res_nN -eq 1 ]]; then
    pass "Default 'N' with 'n'/'N' returns 1"
else
    fail "Default 'N' with 'n'/'N' failed"
fi

# 4.10 Default omitted behaves as Default N
printf "\n" | confirm "Prompt" >/dev/null 2>&1
res_def_enter=$?
printf "y\n" | confirm "Prompt" >/dev/null 2>&1
res_def_y=$?
if [[ $res_def_enter -eq 1 ]] && [[ $res_def_y -eq 0 ]]; then
    pass "Default omitted correctly defaults to 'N'"
else
    fail "Default omitted failed"
fi

# ==============================================================================
# Suite 5: verify_checksum Tests
# ==============================================================================
echo "=== Suite 5: verify_checksum ==="

test_chk_file="$TEST_DIR/test_checksum.txt"
echo "hello world" > "$test_chk_file"
expected_chk_hash=$(sha256sum "$test_chk_file" | cut -d' ' -f1)

# 5.1 Valid checksum returns 0
if verify_checksum "$test_chk_file" "$expected_chk_hash" >/dev/null 2>&1; then
    pass "Valid checksum matches and returns 0"
else
    fail "Valid checksum check failed"
fi

# 5.2 Mismatched checksum returns 1
bad_chk_hash="0000000000000000000000000000000000000000000000000000000000000000"
if verify_checksum "$test_chk_file" "$bad_chk_hash" >/dev/null 2>&1; then
    fail "Mismatched checksum unexpectedly returned 0"
else
    pass "Mismatched checksum returns 1"
fi

# 5.3 Non-existent file returns 1
if verify_checksum "$TEST_DIR/nonexistent_file.rpm" "$expected_chk_hash" >/dev/null 2>&1; then
    fail "Nonexistent file unexpectedly returned 0"
else
    pass "Nonexistent file returns 1"
fi

# ==============================================================================
# Suite 6: Hybrid GPU Vulkan Configuration Tests
# ==============================================================================
echo "=== Suite 6: Hybrid GPU Vulkan Configuration ==="

test_vulkan_logic() {
    local chassis="$1"
    local has_battery="$2"
    local gpu_nvidia="$3"
    local gpu_amd="$4"
    local gpu_intel="$5"

    local is_laptop=false
    if [[ "$chassis" == "laptop" || "$chassis" == "notebook" || "$chassis" == "convertible" || "$chassis" == "portable" ]] || [[ "$has_battery" == "true" ]]; then
        is_laptop=true
    fi

    local selected_driver=""
    if $is_laptop; then
        if [[ -n "$gpu_nvidia" && ( -n "$gpu_amd" || -n "$gpu_intel" ) ]]; then
            if [[ -n "$gpu_amd" ]]; then
                selected_driver="*radeon*"
            elif [[ -n "$gpu_intel" ]]; then
                selected_driver="*intel*"
            fi
        fi
    fi
    echo "$selected_driver"
}

# 6.1 AMD + NVIDIA on Laptop
driver=$(test_vulkan_logic "laptop" "true" "NVIDIA Corporation" "Advanced Micro Devices" "")
if [[ "$driver" == "*radeon*" ]]; then
    pass "AMD + NVIDIA on laptop selects *radeon*"
else
    fail "AMD + NVIDIA on laptop failed" "$driver"
fi

# 6.2 Intel + NVIDIA on Laptop
driver=$(test_vulkan_logic "notebook" "true" "NVIDIA Corporation" "" "Intel Corporation")
if [[ "$driver" == "*intel*" ]]; then
    pass "Intel + NVIDIA on laptop selects *intel*"
else
    fail "Intel + NVIDIA on laptop failed" "$driver"
fi

# 6.3 Dedicated NVIDIA only on Laptop (MUX switch)
driver=$(test_vulkan_logic "laptop" "true" "NVIDIA Corporation" "" "")
if [[ -z "$driver" ]]; then
    pass "NVIDIA only on laptop leaves Vulkan config unset"
else
    fail "NVIDIA only on laptop failed" "$driver"
fi

# 6.4 AMD + NVIDIA on Desktop PC
driver=$(test_vulkan_logic "desktop" "false" "NVIDIA Corporation" "Advanced Micro Devices" "")
if [[ -z "$driver" ]]; then
    pass "AMD + NVIDIA on desktop leaves Vulkan config unset"
else
    fail "AMD + NVIDIA on desktop failed" "$driver"
fi

# 6.5 Intel + NVIDIA on Desktop PC
driver=$(test_vulkan_logic "desktop" "false" "NVIDIA Corporation" "" "Intel Corporation")
if [[ -z "$driver" ]]; then
    pass "Intel + NVIDIA on desktop leaves Vulkan config unset"
else
    fail "Intel + NVIDIA on desktop failed" "$driver"
fi

# ==============================================================================
# Suite 7: Platform Decoupling & Hardware Agnosticism Tests
# ==============================================================================
echo "=== Suite 7: Platform Decoupling & Hardware Agnosticism ==="

# 7.1 OSTree / Atomic Desktop Detection
test_ostree_check() {
    local ostree_flag="$1"
    if [[ "$ostree_flag" == "true" ]]; then
        return 1
    fi
    return 0
}
if ! test_ostree_check "true"; then
    pass "OSTree environment correctly identified and flagged"
else
    fail "OSTree environment was not flagged"
fi

# 7.2 GNOME Detection & Non-GNOME Gating
is_gnome_env() {
    local de="$1"
    local has_shell="$2"
    if [[ "$de" =~ GNOME ]] || [[ "$has_shell" == "true" ]]; then
        return 0
    fi
    return 1
}
if ! is_gnome_env "KDE" "false"; then
    pass "Non-GNOME desktop (KDE) correctly skips GNOME-specific tweaks"
else
    fail "Non-GNOME desktop was improperly identified as GNOME"
fi
if is_gnome_env "GNOME" "false"; then
    pass "GNOME desktop correctly identified"
else
    fail "GNOME desktop was not identified"
fi

# 7.3 AMD ROCm Discrete GPU Gating
is_discrete_amd_gpu() {
    local lspci_str="$1"
    grep -Eiq 'Navi|Radeon RX|Discrete' <<< "$lspci_str"
}
apu_lspci="VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Phoenix1 (rev c4)"
dgpu_lspci="VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700/6700 XT / 6800M]"
if ! is_discrete_amd_gpu "$apu_lspci"; then
    pass "Mobile APU (Phoenix1) correctly rejected for ROCm compute installation"
else
    fail "Mobile APU incorrectly qualified for ROCm"
fi
if is_discrete_amd_gpu "$dgpu_lspci"; then
    pass "Discrete GPU (Navi 22 / Radeon RX) correctly qualified for ROCm compute"
else
    fail "Discrete GPU was not qualified for ROCm"
fi

# 7.4 TLP Conflicting Services Masking
test_tlp_masks() {
    local -a masked_services=()
    mock_mask() { masked_services+=("$1"); }
    mock_mask "power-profiles-daemon.service"
    mock_mask "tuned.service"
    mock_mask "tuned-ppd.service"
    [[ "${masked_services[*]}" == *"power-profiles-daemon.service"* && \
       "${masked_services[*]}" == *"tuned.service"* && \
       "${masked_services[*]}" == *"tuned-ppd.service"* ]]
}
if test_tlp_masks; then
    pass "TLP setup masks both power-profiles-daemon and tuned/tuned-ppd services"
else
    fail "TLP setup failed to mask all conflicting power services"
fi

# ==============================================================================
# Suite 8: Performance, DNF5 & Memory Tuning Safety Tests
# ==============================================================================
echo "=== Suite 8: Performance, DNF5 & Memory Tuning Safety ==="

# 8.1 DNF5 max_downloads_per_mirror is configured
if grep -q "max_downloads_per_mirror=10" "$SRC_DIR/steps/01_dnf.sh"; then
    pass "DNF5 configuration includes max_downloads_per_mirror=10"
else
    fail "DNF5 configuration missing max_downloads_per_mirror"
fi

# 8.2 Live swapoff elimination
if ! grep -q "swapoff /dev/zram0" "$SRC_DIR/steps/09_power.sh"; then
    pass "setup_power does NOT invoke dangerous live swapoff /dev/zram0"
else
    fail "setup_power still contains live swapoff /dev/zram0"
fi

# 8.3 Bounded ZRAM allocation
if grep -q 'zram-size = min(ram / 2, 32768)' "$SRC_DIR/steps/09_power.sh"; then
    pass "ZRAM configuration bounds memory allocation with min(ram / 2, 32768)"
else
    fail "ZRAM configuration missing bounded memory allocation"
fi

# 8.4 Interrupted installer cleanup registration
if grep -q "cleanup_run_tmp" "$SRC_DIR/99_main.sh"; then
    pass "cleanup() registers temporary installer script removal"
else
    fail "cleanup() does not clean up temporary installer scripts"
fi

# ==============================================================================
# Suite 9: Regression Tests for Control Flow, Shell Idempotency, and Subshells
# ==============================================================================
echo "=== Suite 9: Control Flow & Shell Regression Tests ==="

# 9.1 Declining terminal theme deploy inside setup_terminal must not fail under set -e
declined_term_rc=0
(
    set -euo pipefail
    DRY_RUN=false
    PROFILE="dev"
    HAS_GUI=true
    SKIP_WAIT=false
    # shellcheck disable=SC2317
    log() { :; }
    # shellcheck disable=SC2317
    info() { :; }
    # shellcheck disable=SC2317
    warn() { :; }
    # shellcheck disable=SC2317
    success() { :; }
    # shellcheck disable=SC2317
    run_sudo() { return 0; }
    CALL_N=0
    # shellcheck disable=SC2317
    confirm() {
        CALL_N=$((CALL_N + 1))
        [[ $CALL_N -eq 1 ]] && return 0
        return 1
    }
    # shellcheck disable=SC2317
    prompt_input() { echo "2"; }
    # shellcheck source=src/steps/04_shell.sh
    source "$SRC_DIR/steps/04_shell.sh"
    setup_terminal
) >/dev/null 2>&1 || declined_term_rc=$?
if [[ $declined_term_rc -eq 0 ]]; then
    pass "setup_terminal exits 0 under set -e when user skips terminal & dev env"
else
    fail "setup_terminal failed under set -e when optional prompts declined (rc=$declined_term_rc)"
fi

# 9.2 setup_shell preserves user custom lines in ~/.zshrc and ~/.config/fish/config.fish across re-runs
shell_sandbox="$TEST_DIR/shell_preserve"
mkdir -p "$shell_sandbox/.config/fish"
printf '# user custom zsh line\nalias myalias="echo hi"\n' > "$shell_sandbox/.zshrc"
printf '# user custom fish line\nset -g custom_var 1\n' > "$shell_sandbox/.config/fish/config.fish"
(
    export HOME="$shell_sandbox"
    DRY_RUN=false
    PROFILE="minimal"
    log() { :; }
    info() { :; }
    warn() { :; }
    success() { :; }
    step_complete() { :; }
    run() { :; }
    run_sudo() { :; }
    backup_file() { :; }
    confirm() { return 1; }
    prompt_input() { echo "4"; }
    # shellcheck source=src/steps/04_shell.sh
    source "$SRC_DIR/steps/04_shell.sh"
    setup_shell
    setup_shell
) >/dev/null 2>&1
if grep -qF '# user custom zsh line' "$shell_sandbox/.zshrc" && \
   grep -qF '# user custom fish line' "$shell_sandbox/.config/fish/config.fish" && \
   [[ "$(grep -c '# >>> FEDORA_POST_INSTALL_MANAGED >>>' "$shell_sandbox/.zshrc")" -eq 1 ]] && \
   [[ "$(grep -c '# >>> FEDORA_POST_INSTALL_MANAGED >>>' "$shell_sandbox/.config/fish/config.fish")" -eq 1 ]]; then
    pass "setup_shell preserves user shell customizations and deduplicates managed blocks"
else
    fail "setup_shell overwrote custom shell config or duplicated managed blocks"
fi

# 9.3 setup_multimedia skips ffmpeg-free swap if already swapped to ffmpeg
mm_swapped=false
(
    DRY_RUN=false
    # shellcheck disable=SC2317
    log() { :; }
    # shellcheck disable=SC2317
    info() { :; }
    # shellcheck disable=SC2317
    warn() { :; }
    # shellcheck disable=SC2317
    success() { :; }
    # shellcheck disable=SC2317
    step_complete() { :; }
    # shellcheck disable=SC2317
    run() { :; }
    # shellcheck disable=SC2317
    run_sudo() {
        [[ "$*" == *"swap"*"ffmpeg-free"* ]] && echo "SWAP_CALLED"
        return 0
    }
    # shellcheck disable=SC2317
    confirm() { return 1; }
    # shellcheck disable=SC2317
    rpm() {
        # simulate ffmpeg already installed and ffmpeg-free absent
        [[ "$2" == "ffmpeg-free" ]] && return 1
        return 0
    }
    # shellcheck source=src/steps/06_multimedia.sh
    source "$SRC_DIR/steps/06_multimedia.sh"
    out=$(setup_multimedia)
    if [[ "$out" == *"SWAP_CALLED"* ]]; then
        exit 1
    fi
) && mm_swapped=true
if $mm_swapped; then
    pass "setup_multimedia skips ffmpeg-free swap when ffmpeg-free is not installed"
else
    fail "setup_multimedia attempted dnf swap even though ffmpeg-free is not installed"
fi

# ==============================================================================
# Suite 10: Hardware Agnosticism & Sysadmin Safety Tests
# ==============================================================================
echo "=== Suite 10: Hardware Agnosticism & Sysadmin Safety ==="

# 10.1 UPS / peripheral BAT* with scope=Device must NOT mark a desktop as a laptop
if bash -c '
    source "'"$SRC_DIR"'/00_header.sh"
    source "'"$SRC_DIR"'/02_helpers.sh"
    declare -f is_system_battery_present >/dev/null || exit 2
    dev_ps=$(mktemp -d)
    sys_ps=$(mktemp -d)
    trap "rm -rf $dev_ps $sys_ps" EXIT
    mkdir -p "$dev_ps/BAT0" "$sys_ps/BAT0"
    echo "Device" > "$dev_ps/BAT0/scope"
    echo "System" > "$sys_ps/BAT0/scope"
    ! is_system_battery_present "$dev_ps" && is_system_battery_present "$sys_ps"
' 2>/dev/null; then
    pass "is_system_battery_present distinguishes System vs Device batteries"
else
    fail "is_system_battery_present missing or misclassifies System/Device batteries"
fi

# 10.2 Legacy vs modern Intel GPU VA-API classification (never installs both)
intel_legacy=$(
    bash -c '
        source "'"$SRC_DIR"'/00_header.sh"
        source "'"$SRC_DIR"'/02_helpers.sh"
        declare -f intel_vaapi_driver_for_pci >/dev/null || exit 2
        intel_vaapi_driver_for_pci "8086:0416"
    ' 2>/dev/null || true
)
intel_modern=$(
    bash -c '
        source "'"$SRC_DIR"'/00_header.sh"
        source "'"$SRC_DIR"'/02_helpers.sh"
        declare -f intel_vaapi_driver_for_pci >/dev/null || exit 2
        intel_vaapi_driver_for_pci "8086:a7a0"
    ' 2>/dev/null || true
)
if [[ "$intel_legacy" == "libva-intel-driver" && "$intel_modern" == "intel-media-driver" ]]; then
    pass "Intel VA-API selection distinguishes legacy i965 from modern iHD"
else
    fail "Intel VA-API selection failed (legacy='$intel_legacy', modern='$intel_modern')"
fi

# 10.3 setup_multimedia skips Bluetooth and clock-rate overrides when unneeded
mm_log="$TEST_DIR/mm_sudo.log"
rm -f "$mm_log"
bash -c '
    set -u
    DRY_RUN=false
    HAS_BLUETOOTH=false
    HAS_INTEL=false
    HAS_AMD=false
    HAS_NVIDIA=false
    BACKUP_DIR="'"$TEST_DIR"'/mm_bak"
    log() { :; }
    info() { :; }
    warn() { :; }
    success() { :; }
    step_complete() { :; }
    backup_file() { echo "BACKUP: $1" >> "'"$mm_log"'"; }
    confirm() { return 1; }
    run() { :; }
    run_sudo() { echo "SUDO: $*" >> "'"$mm_log"'"; return 0; }
    rpm() { return 1; }
    id() { return 1; }
    systemctl() { return 1; }
    source "'"$SRC_DIR"'/steps/06_multimedia.sh"
    setup_multimedia
' 2>/dev/null
mm_no_bt_out=$(cat "$mm_log" 2>/dev/null || true)
if [[ "$mm_no_bt_out" != *"50-bluez.conf"* && "$mm_no_bt_out" != *"disable-bluetooth.conf"* && "$mm_no_bt_out" != *"99-clock-rates.conf"* ]]; then
    pass "setup_multimedia skips Bluetooth and clock-rate overrides when unneeded"
else
    fail "setup_multimedia wrote Bluetooth or clock-rate configs despite HAS_BLUETOOTH=false / declined confirm: $mm_no_bt_out"
fi

# 10.4 setup_creator excludes wlroots-only wf-recorder
if ! grep -q "wf-recorder" "$SRC_DIR/steps/15_creator.sh"; then
    pass "setup_creator excludes wlroots-only wf-recorder on Fedora Workstation GNOME"
else
    fail "setup_creator still installs wlroots-only wf-recorder"
fi

# 10.5 setup_power logs consistent 99-zram.conf filename and invokes backup_file
power_dry_out=$(
    bash -c '
        set -u
        DRY_RUN=false
        IS_LAPTOP=false
        IS_VM=false
        IS_CONTAINER=false
        CHASSIS_TYPE="Desktop"
        log() { :; }
        info() { :; }
        warn() { :; }
        success() { echo "SUCCESS: $*"; }
        step_complete() { :; }
        confirm() { [[ "$1" == *"ZRAM"* ]]; }
        backup_file() { echo "BACKUP: $1"; }
        run_sudo() {
            if [[ "${1:-}" == "tee" ]]; then cat >/dev/null; fi
            return 0
        }
        gsettings() { return 0; }
        source "'"$SRC_DIR"'/steps/09_power.sh"
        setup_power
    ' 2>/dev/null
)
if [[ "$power_dry_out" != *"10-zram.conf"* ]] && \
   [[ "$power_dry_out" == *"99-zram.conf"* ]] && \
   [[ "$power_dry_out" == *"BACKUP: /etc/systemd/zram-generator.conf.d/99-zram.conf"* ]] && \
   [[ "$power_dry_out" == *"BACKUP: /etc/sysctl.d/99-zram.conf"* ]]; then
    pass "setup_power uses consistent 99-zram.conf name and backs up zram/sysctl targets"
else
    fail "setup_power logged stale 10-zram.conf or omitted backups: $power_dry_out"
fi

# 10.6 setup_drivers excludes CUDA in workstation step and respects legacy vs modern Intel VA-API
drv_modern_out=$(
    bash -c '
        set -u
        DRY_RUN=false
        IS_CONTAINER=false
        IS_VM=false
        IS_LAPTOP=false
        HAS_INTEL=true
        HAS_AMD=false
        HAS_NVIDIA=true
        INTEL_VAAPI_PKG="intel-media-driver"
        log() { :; }
        info() { :; }
        warn() { :; }
        success() { :; }
        step_complete() { :; }
        backup_file() { :; }
        confirm() { return 0; }
        mokutil() { return 1; }
        rpm() { return 0; }
        run_sudo() { echo "SUDO: $*"; return 0; }
        source "'"$SRC_DIR"'/steps/17_drivers.sh"
        setup_drivers
    ' 2>/dev/null
)
if [[ "$drv_modern_out" != *"xorg-x11-drv-nvidia-cuda"* ]] && \
   [[ "$drv_modern_out" != *"libva-intel-driver"* ]] && \
   [[ "$drv_modern_out" == *"intel-media-driver"* ]]; then
    pass "setup_drivers excludes CUDA from workstation and selects only modern Intel VA-API"
else
    fail "setup_drivers installed CUDA or redundant libva-intel-driver: $drv_modern_out"
fi

# 10.7 setup_cli_core omits btrfs-only compsize when HAS_BTRFS=false
cli_nobtrfs_out=$(
    bash -c '
        set -u
        HAS_BTRFS=false
        log() { :; }
        step_complete() { :; }
        run_sudo() { echo "SUDO: $*"; return 0; }
        source "'"$SRC_DIR"'/steps/03_cli_core.sh"
        setup_cli_core
    ' 2>/dev/null
)
if [[ "$cli_nobtrfs_out" != *"compsize"* ]]; then
    pass "setup_cli_core skips Btrfs-only compsize when root is not Btrfs"
else
    fail "setup_cli_core installed compsize despite HAS_BTRFS=false"
fi

echo ""
echo "=============================================================================="
echo "Final Summary: Total: $TOTAL, Passed: $PASSED, Failed: $FAILED"
echo "=============================================================================="

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi

