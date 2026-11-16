#!/usr/bin/env bash
# ==============================================================================
# Fedora Post-Install Setup Script
# Author: Kushagra Kumar
# Version: 9.0.0
# Repository: https://github.com/kk376/fedora-post-install
# ==============================================================================

# Non-root invocation guard: prevent running entire orchestrator with sudo/root
if [[ ${EUID:-$(id -u)} -eq 0 && "${ALLOW_ROOT:-false}" != "true" ]]; then
    echo -e "\033[0;31m[ERROR]\033[0m Do not run this script as root or with sudo." >&2
    echo -e "The script invokes sudo internally for privileged operations." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

# Remote Execution Bootstrap:
# When piped via curl (e.g. curl -fsSL ... | bash), BASH_SOURCE is /dev/fd/* or stdin,
# so the local ./src directory does not exist. Fetch archive and run locally.
if [[ -z "${SCRIPT_DIR}" || ! -d "${SCRIPT_DIR}/src" ]]; then
    TMP_DIR=$(mktemp -d /tmp/fedora-post-install.XXXXXX)
    trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
    echo -e "\033[0;34m[SETUP]\033[0m Fetching fedora-post-install from GitHub..."
    curl -fsSL "https://github.com/kk376/fedora-post-install/archive/refs/heads/main.tar.gz" \
        | tar -xz -C "$TMP_DIR" --strip-components=1
    if [[ -f "$TMP_DIR/setup.sh" ]]; then
        bash "$TMP_DIR/setup.sh" "$@"
        exit $?
    fi
fi

# Local Execution: Source Core Runtime
source "${SCRIPT_DIR}/src/00_header.sh"
source "${SCRIPT_DIR}/src/01_cli.sh"
source "${SCRIPT_DIR}/src/02_helpers.sh"
source "${SCRIPT_DIR}/src/03_profiles.sh"

# Source Step Modules
for step_file in "${SCRIPT_DIR}/src/steps/"*.sh; do
    # shellcheck source=/dev/null
    source "$step_file"
done

# Source Orchestrator & Entrypoint Runner
source "${SCRIPT_DIR}/src/99_main.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    trap 'echo -e "\n${RED}Interrupted by user${NC}"; cleanup; exit 1' INT TERM
    trap cleanup EXIT
    main "$@"
fi
