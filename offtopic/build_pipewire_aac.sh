#!/bin/bash

set -e

# Renkler ve Log Fonksiyonları (Senin orijinal formatın)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_DIR="$(pwd)"
WORK_DIR="$BASE_DIR/build_workspace"
OUTPUT_DIR="$BASE_DIR/output"
LOG_FILE="$OUTPUT_DIR/nonfree_build_log.txt"

log_header() { echo -e "${BLUE}:: $1${NC}" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"; }
run_silent() {
    local message="$1"; shift
    echo -ne "${YELLOW}-> ${message}...${NC}"
    if "$@" >> "$LOG_FILE" 2>&1; then echo -e " ${GREEN}Done.${NC}"; else echo -e " ${RED}FAILED!${NC}"; exit 1; fi
}

prepare_nonfree_env() {
    mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
    log_header "Non-Free Environment Preparation"
    run_silent "Enabling non-free components" sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/g' /etc/apt/sources.list.d/debian.sources
    run_silent "Updating package lists" apt-get update -qq
}

build_pipewire_aac() {
    log_header "Building Patched PipeWire (AAC/LDAC Support)"
    cd "$WORK_DIR"
    rm -rf pipewire*
    run_silent "Fetching PipeWire source" apt-get source pipewire
    PW_DIR=$(find . -maxdepth 1 -type d -name "pipewire-*" | head -n 1)
    cd "$PW_DIR"
    run_silent "Enabling AAC/LDAC in rules" sed -i 's/-Dbluez5-codec-aac=disabled/-Dbluez5-codec-aac=enabled/g' debian/rules
    sed -i 's/-Dbluez5-codec-ldac=disabled/-Dbluez5-codec-ldac=enabled/g' debian/rules
    sed -i 's/Build-Depends:/Build-Depends: libfdk-aac-dev, libldacbt-enc-dev,/' debian/control
    run_silent "Installing build-deps" mk-build-deps --install --remove --tool 'apt-get -y --no-install-recommends' debian/control
    log_header "Compiling PipeWire (This may take a while)"
    run_silent "Building DEB packages" dpkg-buildpackage -us -uc -b -j$(nproc) --no-check
    mv ../*.deb "$OUTPUT_DIR"/ 2>/dev/null
    log_success "PipeWire AAC/LDAC packages are ready in output folder."
}

prepare_nonfree_env
build_pipewire_aac
