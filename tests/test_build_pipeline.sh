#!/usr/bin/env bash
# ==============================================================================
# Test Suite for Fedora Post-Install Build Pipeline (build.sh)
# Covers: CLI options, module presence, assembly integrity, --check, --stdout
# ==============================================================================

set -u

TOTAL=0
PASSED=0
FAILED=0

GREEN='\033[0;32m'
RED='\033[0;31m'
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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="${ROOT_DIR}/build.sh"
SETUP_SCRIPT="${ROOT_DIR}/setup.sh"

TEST_SANDBOX=$(mktemp -d)
trap 'rm -rf "$TEST_SANDBOX"' EXIT

echo "========================================================"
echo "Running Build Pipeline Test Suite (build.sh)"
echo "Target: $BUILD_SCRIPT"
echo "========================================================"

# ==============================================================================
# Suite 1: CLI Argument Handling
# ==============================================================================
echo "--- Suite 1: CLI Argument Handling ---"

help_out=$("$BUILD_SCRIPT" --help 2>&1)
help_code=$?
if [[ $help_code -eq 0 ]] && echo "$help_out" | grep -q "Usage:"; then
    pass "--help displays usage and exits 0"
else
    fail "--help failed" "Exit code: $help_code"
fi

short_help_out=$("$BUILD_SCRIPT" -h 2>&1)
short_help_code=$?
if [[ $short_help_code -eq 0 ]] && echo "$short_help_out" | grep -q "Usage:"; then
    pass "-h displays usage and exits 0"
else
    fail "-h failed" "Exit code: $short_help_code"
fi

invalid_out=$("$BUILD_SCRIPT" --non-existent-option 2>&1) || invalid_code=$?
if [[ ${invalid_code:-0} -eq 1 ]] && echo "$invalid_out" | grep -q "Unknown option"; then
    pass "Invalid option exits 1 with unknown option warning"
else
    fail "Invalid option did not exit 1 correctly"
fi

missing_arg_out=$("$BUILD_SCRIPT" -o 2>&1) || missing_arg_code=$?
if [[ ${missing_arg_code:-0} -eq 1 ]] && echo "$missing_arg_out" | grep -q "Missing argument"; then
    pass "Missing argument for -o exits 1"
else
    fail "Missing argument for -o did not fail as expected"
fi

# ==============================================================================
# Suite 2: Module Source Verification
# ==============================================================================
echo "--- Suite 2: Module Source Verification ---"

EXPECTED_MODULES=(
    "src/00_header.sh"
    "src/01_cli.sh"
    "src/02_helpers.sh"
    "src/03_profiles.sh"
    "src/steps/01_dnf.sh"
    "src/steps/02_dns.sh"
    "src/steps/03_cli_core.sh"
    "src/steps/04_shell.sh"
    "src/steps/05_fonts.sh"
    "src/steps/06_multimedia.sh"
    "src/steps/07_gnome.sh"
    "src/steps/08_desktop_apps.sh"
    "src/steps/09_power.sh"
    "src/steps/10_dev.sh"
    "src/steps/11_editor.sh"
    "src/steps/12_docker.sh"
    "src/steps/13_kvm.sh"
    "src/steps/14_gaming.sh"
    "src/steps/15_creator.sh"
    "src/steps/16_reboot.sh"
    "src/steps/17_drivers.sh"
    "src/99_main.sh"
)

all_modules_ok=true
for mod in "${EXPECTED_MODULES[@]}"; do
    if [[ ! -s "${ROOT_DIR}/${mod}" ]]; then
        all_modules_ok=false
        fail "Module $mod is missing or empty"
        break
    fi
done

if $all_modules_ok; then
    pass "All 22 modular source files exist and are non-empty"
fi

# ==============================================================================
# Suite 3: Build Assembly & Output Verification
# ==============================================================================
echo "--- Suite 3: Build Assembly & Output Verification ---"

test_out="${TEST_SANDBOX}/test_setup.sh"
build_out=$("$BUILD_SCRIPT" -o "$test_out" 2>&1)
build_code=$?

if [[ $build_code -eq 0 ]] && [[ -f "$test_out" ]]; then
    pass "build.sh writes successfully to custom output path"
else
    fail "build.sh custom output failed" "Exit code: $build_code, output: $build_out"
fi

if [[ -x "$test_out" ]]; then
    pass "Assembled output file is marked executable (+x)"
else
    fail "Assembled output file is missing executable permission"
fi

if head -n 1 "$test_out" | grep -q '^#!/bin/bash'; then
    pass "Assembled script starts with #!/bin/bash shebang"
else
    fail "Assembled script missing proper shebang"
fi

if tail -n 5 "$test_out" | grep -q 'main "\$@"'; then
    pass "Assembled script terminates with entrypoint main runner"
else
    fail "Assembled script missing main runner"
fi

# ==============================================================================
# Suite 4: Synchronization Check (--check)
# ==============================================================================
echo "--- Suite 4: Synchronization Check (--check) ---"

check_code=0
check_out=$("$BUILD_SCRIPT" --check -o "$test_out" 2>&1) || check_code=$?
if [[ $check_code -eq 0 ]] && echo "$check_out" | grep -q "synchronized"; then
    pass "--check succeeds for synchronized target bundle"
else
    fail "--check failed on synchronized bundle" "Exit code: $check_code, output: $check_out"
fi

# Test desynchronization detection
desync_target="${TEST_SANDBOX}/desync_setup.sh"
cp "$test_out" "$desync_target"
echo "# Desync comment" >> "$desync_target"

desync_code=0
desync_out=$("$BUILD_SCRIPT" --check -o "$desync_target" 2>&1) || desync_code=$?
if [[ $desync_code -eq 1 ]] && echo "$desync_out" | grep -q "out of sync"; then
    pass "--check correctly detects out-of-sync destination"
else
    fail "--check failed to detect out-of-sync file" "Exit code: $desync_code"
fi

# Test missing destination detection
missing_code=0
missing_out=$("$BUILD_SCRIPT" --check -o "${TEST_SANDBOX}/non_existent.sh" 2>&1) || missing_code=$?
if [[ $missing_code -eq 1 ]] && echo "$missing_out" | grep -q "does not exist"; then
    pass "--check fails when target output file does not exist"
else
    fail "--check handled missing file incorrectly" "Exit code: $missing_code"
fi

# ==============================================================================
# Suite 5: Standard Output Mode (--stdout)
# ==============================================================================
echo "--- Suite 5: Standard Output Mode (--stdout) ---"

stdout_target="${TEST_SANDBOX}/stdout_setup.sh"
"$BUILD_SCRIPT" --stdout > "$stdout_target"

if cmp -s "$stdout_target" "$test_out"; then
    pass "--stdout emits byte-for-byte identical content to assembled bundle"
else
    fail "--stdout content differs from assembled bundle"
fi

# ==============================================================================
# Suite 6: Remote Bootstrap Execution Fallback
# ==============================================================================
echo "--- Suite 6: Remote Bootstrap Execution Fallback ---"

remote_sandbox="${TEST_SANDBOX}/remote_test"
mkdir -p "$remote_sandbox/bin"
cp "$SETUP_SCRIPT" "$remote_sandbox/remote_setup.sh"

# Mock curl and tar in remote sandbox to simulate pipe/download execution
cat << 'MOCK_REMOTE' > "$remote_sandbox/bin/curl"
#!/bin/bash
exit 0
MOCK_REMOTE
chmod +x "$remote_sandbox/bin/curl"

# Verify remote setup.sh identifies missing src/ and attempts remote fetch
bootstrap_out=$(PATH="$remote_sandbox/bin:$PATH" bash "$remote_sandbox/remote_setup.sh" --help 2>&1 || true)
if echo "$bootstrap_out" | grep -q "Fetching fedora-post-install from GitHub"; then
    pass "setup.sh self-bootstraps from GitHub when executed remotely without local src/"
else
    fail "setup.sh failed to trigger remote bootstrap when local src/ is missing"
fi

echo "========================================================"
echo "SUMMARY: Total: $TOTAL, Passed: $PASSED, Failed: $FAILED"
echo "========================================================"

if [[ $FAILED -eq 0 ]]; then
    exit 0
else
    exit 1
fi
