#!/bin/bash

# Thanks to Hasan Bıyık (hbiyik) for patch

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_DIR="$(pwd)"
WORK_DIR="$BASE_DIR/build_workspace"
OUTPUT_DIR="$BASE_DIR/output"
LOG_FILE="$OUTPUT_DIR/build_firefox_log_$(date +%Y%m%d).txt"

FIREFOX_VERSION="139.0.4-1"
GECKO_BASE="4c065f1df299065c305fb48b36cdae571a43d97c"
GECKO_BRANCH="mpp-release"
PATCH_URL="https://github.com/hbiyik/gecko-dev/compare/${GECKO_BASE}...${GECKO_BRANCH}.patch"

log_header() {
    echo -e "${BLUE}:: $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"
}

run_silent() {
    local message="$1"
    shift
    echo -ne "${YELLOW}-> ${message}...${NC}"
    if "$@" >> "$LOG_FILE" 2>&1; then
        echo -e " ${GREEN}Done.${NC}"
    else
        echo -e " ${RED}FAILED!${NC}"
        log_error "Process failed while: $message"
        echo -e "${RED}Check $LOG_FILE for details.${NC}"
        exit 1
    fi
}

prepare_environment() {
    mkdir -p "$WORK_DIR"
    mkdir -p "$OUTPUT_DIR"
    log_header "Environment Preparation"
    if [ -z "$CI" ]; then
         run_silent "Updating apt sources" sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/*.sources
         run_silent "Updating package lists" apt-get update -qq
    fi
}

install_build_deps() {
    log_header "Installing Build Dependencies"
    run_silent "Installing build dependencies via mk-build-deps" \
        mk-build-deps --install --remove --tool 'apt-get -y --no-install-recommends' debian/control
}

build_firefox_mpp() {
    log_header "Build Process: firefox"
    cd "$WORK_DIR"
    rm -rf firefox*
    log_header "Fetching Source Code"
    if [ ! -d "firefox" ]; then
        run_silent "Cloning" \
            git clone https://salsa.debian.org/mozilla-team/firefox.git firefox
    fi
    cd firefox
    run_silent "Checking out tag: $FIREFOX_VERSION" git checkout -f "$FIREFOX_VERSION"
    log_header "Applying Rockchip MPP Patch"
    run_silent "Downloading patch" wget -nv "$PATCH_URL" -O mpp.patch
    run_silent "Applying mpp.patch" patch -p1 --ignore-whitespace -i mpp.patch
    install_build_deps
    log_header "Compiling Firefox (This will take a long time)"
    run_silent "Building firefox package" dpkg-buildpackage -us -uc -b -j$(nproc)
    mv ../*.deb "$OUTPUT_DIR"/ 2>/dev/null
    log_success "firefox built successfully."
}

prepare_environment
echo "--- Firefox Build Run Started: $(date) ---" > "$LOG_FILE"

build_firefox_mpp

log_header "Firefox build completed!"
echo -e "${GREEN}Artifacts are located in: $OUTPUT_DIR${NC}"
echo "--- Run Finished: $(date) ---" | tee -a "$LOG_FILE"
