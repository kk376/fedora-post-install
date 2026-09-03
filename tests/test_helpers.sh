#!/bin/bash
# shellcheck disable=SC1090,SC2181,SC2016,SC2034
# Test Suite for setup.sh Helper Functions
# Covers: set_zshrc_line, github_download, check_disk_space, confirm
set -u

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
            echo "downloaded from: $2" > "$2"
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
if [[ $? -eq 0 ]] && [[ "$out" == *"Could not determine free disk space"* ]]; then
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

echo ""
echo "=============================================================================="
echo "Final Summary: Total: $TOTAL, Passed: $PASSED, Failed: $FAILED"
echo "=============================================================================="

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
