#!/usr/bin/env bash
# ==============================================================================
# Fedora Post-Install Build & Module Bundler
# Concatenates modular source files from src/ into a unified setup.sh artifact.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
SRC_DIR="$ROOT_DIR/src"
DEFAULT_OUTPUT="$ROOT_DIR/dist/setup.sh"
OUTPUT_FILE="$DEFAULT_OUTPUT"

CHECK_MODE=false
STDOUT_MODE=false

# Terminal colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Ordered list of modular source files
MODULES=(
    "00_header.sh"
    "01_cli.sh"
    "02_helpers.sh"
    "03_profiles.sh"
    "steps/01_dnf.sh"
    "steps/02_dns.sh"
    "steps/03_cli_core.sh"
    "steps/04_shell.sh"
    "steps/05_fonts.sh"
    "steps/06_multimedia.sh"
    "steps/07_gnome.sh"
    "steps/07b_debloat.sh"
    "steps/08_desktop_apps.sh"
    "steps/09_power.sh"
    "steps/10_dev.sh"
    "steps/11_editor.sh"
    "steps/12_docker.sh"
    "steps/13_kvm.sh"
    "steps/14_gaming.sh"
    "steps/15_creator.sh"
    "steps/16_reboot.sh"
    "steps/17_drivers.sh"
    "99_main.sh"
)

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build pipeline that concatenates modular source files in src/ into setup.sh.

Options:
  --check        Verify that setup.sh is in sync with src/ without modifying files.
                 Exits 0 if synchronized, exits 1 if out of sync.
  --stdout       Output the assembled script to stdout instead of writing to file.
  -o, --output   Specify custom output file path (default: setup.sh).
  -h, --help     Show this help message and exit.
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_MODE=true
            shift
            ;;
        --stdout)
            STDOUT_MODE=true
            shift
            ;;
        -o|--output)
            if [[ -z "${2:-}" ]]; then
                error "Missing argument for $1"
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --output=*)
            OUTPUT_FILE="${1#*=}"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help >&2
            exit 1
            ;;
    esac
done

# Validate that all modules exist
for mod in "${MODULES[@]}"; do
    mod_path="$SRC_DIR/$mod"
    if [[ ! -f "$mod_path" ]]; then
        error "Source module missing: $mod_path"
        exit 1
    fi
done

# Create a temporary file for assembly in the output directory
OUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p "$OUT_DIR"
TMP_BUNDLE=$(mktemp "${OUT_DIR}/.bundle.tmp.XXXXXX")
trap 'rm -f "$TMP_BUNDLE"' EXIT

# Concatenate all modules in order
for mod in "${MODULES[@]}"; do
    cat "$SRC_DIR/$mod" >> "$TMP_BUNDLE"
done

# Ensure single trailing newline
if [[ -s "$TMP_BUNDLE" && "$(tail -c 1 "$TMP_BUNDLE")" != "" ]]; then
    echo "" >> "$TMP_BUNDLE"
fi

if $STDOUT_MODE; then
    cat "$TMP_BUNDLE"
    exit 0
fi

if $CHECK_MODE; then
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        error "Target output file does not exist: $OUTPUT_FILE"
        error "Run './build.sh' to assemble setup.sh."
        exit 1
    fi

    if cmp -s "$TMP_BUNDLE" "$OUTPUT_FILE"; then
        ok "$OUTPUT_FILE is synchronized with src/ (${#MODULES[@]} modules)."
        exit 0
    else
        error "$OUTPUT_FILE is out of sync with src/ modules!"
        if command -v diff >/dev/null 2>&1; then
            echo -e "${YELLOW}--- Diff preview (first 20 lines) ---${NC}" >&2
            diff -u "$OUTPUT_FILE" "$TMP_BUNDLE" | head -n 20 >&2 || true
        fi
        error "Run './build.sh' to reassemble $OUTPUT_FILE."
        exit 1
    fi
fi

# Atomic write to target file
chmod +x "$TMP_BUNDLE"
mv "$TMP_BUNDLE" "$OUTPUT_FILE"

line_count=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
byte_count=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
ok "Successfully assembled $OUTPUT_FILE (${#MODULES[@]} modules, $line_count lines, $byte_count bytes)."
