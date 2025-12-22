#!/bin/bash

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

FIREFOX_VERSION="debian/139.0.4-1"
GECKO_COMB="4c065f1df299065c305fb48b36cdae571a43d97c"
GECKO_COMI="mpp-release"
PATCH_URL="https://github.com/hbiyik/gecko-dev/compare/${GECKO_COMB}...${GECKO_COMI}.patch"

export DEB_BUILD_OPTIONS="noddebs nocheck nodebug parallel=$(nproc)"
export DEB_BUILD_MAINT_OPTIONS="optimize=-lto"
export MOZ_DEBUG_FLAGS="-g0"
export LDFLAGS="-Wl,--no-keep-memory -Wl,--reduce-memory-overheads"

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
    run_silent "Installing build dependencies via mk-build-deps" mk-build-deps --install --remove --tool 'apt-get -y --no-install-recommends' debian/control
    log_success "Build dependencies installed."
}

apply_optimizations() {
    log_header "Applying Resource Saving Tweaks"
    if [ -f "debian/rules" ]; then
        run_silent "Disabling Debug in rules" sed -i 's/--enable-debug-symbols/--disable-debug-symbols/g' debian/rules
        run_silent "Disabling Tests in rules" sed -i 's/--enable-tests/--disable-tests/g' debian/rules
    fi
    
    echo "Creating .mozconfig"
    cat <<EOF > .mozconfig
export CC=clang
export CXX=clang++
export AR=llvm-ar
export NM=llvm-nm
export RANLIB=llvm-ranlib
export CFLAGS="-march=armv8.2-a+crypto+fp16+rcpc+dotprod -mtune=cortex-a76 -O2"
export CXXFLAGS="-march=armv8.2-a+crypto+fp16+rcpc+dotprod -mtune=cortex-a76 -O2"
export LDFLAGS="-fuse-ld=lld -Wl,--no-keep-memory -Wl,--reduce-memory-overheads"
export RUSTFLAGS="-C debuginfo=0"
ac_add_options --disable-debug
ac_add_options --disable-debug-symbols
ac_add_options --disable-tests
ac_add_options --disable-crashreporter
ac_add_options --disable-telemetry
ac_add_options --disable-firefox-studies
ac_add_options --disable-pocket
ac_add_options --disable-updater
ac_add_options --disable-datareporting
ac_add_options --enable-lto=thin
ac_add_options --enable-optimize
ac_add_options --enable-linker=lld
mk_add_options MOZ_MAKE_FLAGS="$(nproc)"
EOF
    export MOZCONFIG="$(pwd)/.mozconfig"
    log_success "Optimizations applied."
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
    install_build_deps   
    log_header "Applying Rockchip MPP Patch"
    run_silent "Downloading patch" wget -nv "$PATCH_URL" -O mpp.patch
    run_silent "Applying mpp.patch" patch -p1 --ignore-whitespace -i mpp.patch
    apply_optimizations
    log_header "Compiling firefox"
    run_silent "Building firefox package" dpkg-buildpackage -us -uc -b
    mv ../*.deb "$OUTPUT_DIR"/ 2>/dev/null
    log_success "firefox built successfully."
}

prepare_environment
echo "--- Firefox Build Started: $(date) ---" > "$LOG_FILE"

build_firefox_mpp

log_header "Firefox build completed!"
echo -e "${GREEN}Artifacts are located in: $OUTPUT_DIR${NC}"
echo "--- Run Finished: $(date) ---" | tee -a "$LOG_FILE"
