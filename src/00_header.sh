#!/bin/bash
# Fedora 44 Post-Install Setup Script
# Author: Kushagra Kumar
# Version: 8.0.0

# ==============================================================================
# Configuration & Flags
# ==============================================================================
: "${DRY_RUN:=false}"
: "${UNATTENDED:=false}"
: "${BACKUP_DIR:=$HOME/.config/fedora-setup-backups/$(date +%Y%m%d_%H%M%S)}"
: "${LOG_FILE:=/tmp/fedora-setup-$(date +%Y%m%d_%H%M%S).log}"
: "${SCRIPT_VERSION:=8.0.0}"
: "${PROFILE:=workstation}"
: "${DEV_TYPE:=all}"
PROFILE_SPECIFIED=false
DEV_TYPE_SPECIFIED=false
: "${FORCE_RERUN:=false}"
: "${STATE_FILE:=$HOME/.config/fedora-setup/state.txt}"
: "${SUDO_PID:=}"

# System hardware globals (populated by detect_hardware)
SYS_ARCH="$(uname -m)"
IS_LAPTOP=false
CHASSIS_TYPE="Desktop"
HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false

# ==============================================================================
# Colors & Logging
# ==============================================================================
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log()     { echo -e "${BLUE}[SETUP]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
dry()     { echo -e "${MAGENTA}[DRY-RUN]${NC} Would execute: $1"; }

# Progress tracking (managed in parent shell, exported for subshells)
COMPLETED_STEPS=0
FAILED_STEPS=0
SKIPPED_STEPS=0
CURRENT_STEP=0
TOTAL_STEPS=0
START_TIME=$(date +%s)

step_complete() {
    echo -e "\n${GREEN}[${CURRENT_STEP}/${TOTAL_STEPS}]${NC} $1"
}

