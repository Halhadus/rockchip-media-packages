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
LOG_FILE="$OUTPUT_DIR/build_log_$(date +%Y%m%d).txt"

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
        run_silent "Updating apt sources (adding deb-src)" sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/*.sources
        run_silent "Updating package lists" apt-get update -qq
    fi
}

install_build_deps() {
    run_silent "Installing build dependencies" mk-build-deps --install --remove --tool 'apt-get -y --no-install-recommends' debian/control
}

build_v4l_utils() {
    log_header "Build Process: v4l-utils"
    cd "$WORK_DIR"
    rm -rf v4l-utils*
    run_silent "Fetching source code via apt" apt-get source v4l-utils
    V4L_DIR=$(find . -maxdepth 1 -type d -name "v4l-utils*" | head -n 1)
    cd "$V4L_DIR"
    V4L_PATCHES_BASE_URL="https://raw.githubusercontent.com/JeffyCN/meta-rockchip/master/recipes-multimedia/v4l2apps/v4l-utils"
    V4L_PATCHES=(
        "0001-libv4l2-Support-mmap-to-libv4l-plugin.patch"
        "0002-libv4l-mplane-Filter-out-multiplane-formats.patch"
        "0003-libv4l-Disallow-conversion-by-default.patch"
    )
    log_header "Applying Patches for v4l-utils"
    for PATCH_NAME in "${V4L_PATCHES[@]}"; do
        run_silent "Downloading patch: $PATCH_NAME" wget -nv "$V4L_PATCHES_BASE_URL/$PATCH_NAME" -O "$PATCH_NAME"
        run_silent "Applying patch: $PATCH_NAME" patch -p1 < "$PATCH_NAME"
    done
    install_build_deps
    rm -f ../*.deb ../*.changes ../*.buildinfo
    run_silent "Compiling and packaging: v4l-utils" dpkg-buildpackage -us -uc -b
    log_success "v4l-utils built successfully."
    run_silent "Installing generated v4l-utils packages" dpkg -i ../*.deb
    mv ../*.deb "$OUTPUT_DIR"/ 2>/dev/null
}

build_standard_repos() {
    repos=(
        "https://github.com/JeffyCN/mirrors.git linux-rga-multi linux-rga"
        "https://github.com/rockchip-linux/mpp.git develop mpp"
        "https://github.com/JeffyCN/libv4l-rkmpp master libv4l-rkmpp"
        "https://github.com/amazingfate/rockchip-multimedia-config main rockchip-multimedia-config"
        "https://github.com/Halhadus/armbian-opi5plus-halhadus-config main armbian-opi5plus-halhadus-config"
        "https://github.com/JeffyCN/drm-cursor master drm-cursor"
    )

    for repo_info in "${repos[@]}"; do
        read -r URL BRANCH DIR_NAME <<< "$repo_info"
        TARGET_PATH="$WORK_DIR/$DIR_NAME"
        log_header "Build Process: $DIR_NAME"
        if [ ! -d "$TARGET_PATH" ]; then
            run_silent "Cloning repository ($BRANCH)" git clone --depth 1 --single-branch -b "$BRANCH" "$URL" "$TARGET_PATH"
        fi
        cd "$TARGET_PATH" || continue
        install_build_deps
        rm -f ../*.deb ../*.changes ../*.buildinfo
        run_silent "Compiling and packaging: $DIR_NAME" dpkg-buildpackage -us -uc -b
        if [[ "$DIR_NAME" != *"config"* ]]; then
            run_silent "Installing generated packages (runtime deps)" dpkg -i ../*.deb
        fi
        mv ../*.deb "$OUTPUT_DIR"/ 2>/dev/null
        log_success "$DIR_NAME built successfully."
    done
}

build_ffmpeg() {
    log_header "Build Process: ffmpeg"
    cd "$WORK_DIR"
    rm -rf ffmpeg*
    run_silent "Fetching ffmpeg source via apt" apt-get source ffmpeg
    FFMPEG_DIR=$(find . -maxdepth 1 -type d -name "ffmpeg-*" | head -n 1)
    cd "$FFMPEG_DIR"
    FFMPEG_BASE="bcef9167268961bd6cbb214278f9cdef3837843f"
    FFMPEG_BRANCH="7.1"
    FFMPEG_PATCH_URL="https://github.com/nyanmisaka/ffmpeg-rockchip/compare/${FFMPEG_BASE}...${FFMPEG_BRANCH}.patch"
    run_silent "Downloading Rockchip MPP/RGA patch" wget -nv "$FFMPEG_PATCH_URL" -O mpp_rga.patch
    run_silent "Applying Rockchip MPP/RGA patch" patch -p1 < mpp_rga.patch
    echo -e "${YELLOW}-> Modifying debian/rules flags (enable rkmpp/rkrga)...${NC}"
    sed -i '/--enable-libvpx/a \                --enable-version3 \\\n                --enable-rkmpp \\\n                --enable-rkrga \\' debian/rules
    install_build_deps
    run_silent "Compiling and packaging: ffmpeg" dpkg-buildpackage -us -uc -b -j$(nproc)
    mv ../*.deb "$OUTPUT_DIR"/ 2>/dev/null
    log_success "ffmpeg built successfully."
}

prepare_environment

echo "--- Build Run Started: $(date) ---" > "$LOG_FILE"

build_v4l_utils
build_standard_repos
build_ffmpeg

log_header "All tasks completed successfully!"
echo -e "${GREEN}Artifacts are located in: $OUTPUT_DIR${NC}"
echo "--- Run Finished: $(date) ---" | tee -a "$LOG_FILE"
