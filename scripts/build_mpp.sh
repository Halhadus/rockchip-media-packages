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

build_standard_repos() {
    repos=(
        "https://github.com/JeffyCN/mirrors.git linux-rga-multi linux-rga"
        "https://github.com/nyanmisaka/rk-mirrors jellyfin-mpp mpp"
        "https://github.com/JeffyCN/mirrors.git libmali mali"
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
        if [[ "$DIR_NAME" != *"mali"* ]]; then
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
    FFMPEG_BASE="fa4ee7ab3c1734795149f6dbc3746e834e859e8c"
    FFMPEG_BRANCH="8.0"
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

build_standard_repos
build_ffmpeg

log_header "All tasks completed successfully!"
echo -e "${GREEN}Artifacts are located in: $OUTPUT_DIR${NC}"
echo "--- Run Finished: $(date) ---" | tee -a "$LOG_FILE"
