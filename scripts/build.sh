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

export DEB_CFLAGS_APPEND="-O2 -mcpu=cortex-a76.cortex-a55 -mtune=cortex-a76.cortex-a55 -pipe -flto -Wno-error=incompatible-pointer-types"
export DEB_CXXFLAGS_APPEND="-O2 -mcpu=cortex-a76.cortex-a55 -mtune=cortex-a76.cortex-a55 -pipe -flto -Wno-error=incompatible-pointer-types"

export CFLAGS="$DEB_CFLAGS_APPEND"
export CXXFLAGS="$DEB_CXXFLAGS_APPEND"

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
    run_silent "Configuring Git identity" git config --global user.email "eneshakans45@proton.me"
    run_silent "Configuring Git identity" git config --global user.name "Halhadus"
    run_silent "Configuring Git safe directory" git config --global --add safe.directory '*'
}

install_build_deps() {
    run_silent "Installing build dependencies" mk-build-deps --install --remove --tool 'apt-get -y --no-install-recommends' debian/control
}

build_standard_repos() {
    repos=(
        "https://github.com/Halhadus/debian-opi5plus-halhadus-config main debian-opi5plus-halhadus-config"
        "https://github.com/nyanmisaka/rk-mirrors jellyfin-mpp mpp"
    )

    for repo_info in "${repos[@]}"; do
        read -r URL BRANCH DIR_NAME <<< "$repo_info"
        TARGET_PATH="$WORK_DIR/$DIR_NAME"
        log_header "Build Process: $DIR_NAME"
        if [ ! -d "$TARGET_PATH" ]; then
            run_silent "Cloning repository ($BRANCH)" git clone --single-branch -b "$BRANCH" "$URL" "$TARGET_PATH"
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
    run_silent "Downloading v4l2request.diff" wget -nv "https://code.ffmpeg.org/FFmpeg/FFmpeg/compare/86eb07154d0255a5e96c822d8dc7805ade600f0b...Kwiboo:v4l2request-2025-v3-rkvdec.diff" -O v4l2request.diff
    filterdiff -x '*/Changelog' -x '*/.forgejo/CODEOWNERS' v4l2request.diff > clean_v4l2request.diff
    run_silent "Applying clean_v4l2request.diff" patch -p1 -i clean_v4l2request.diff
    echo -e "${YELLOW}-> Modifying debian/rules flags (enable v4l2-request/m2m)...${NC}"
    sed -i '/--enable-libvpx/a \                --enable-v4l2-request \\\n                 --enable-version3 \\\n                --enable-libudev \\\n                --enable-v4l2_m2m \\\n                --enable-libdrm \\\n                --enable-neon \\\n                --enable-rkmpp \\\n                --enable-hwaccels \\' debian/rules
    install_build_deps
    run_silent "Compiling and packaging: ffmpeg" dpkg-buildpackage -us -uc -b -j$(nproc)
    mv ../*.deb "$OUTPUT_DIR"/ 2>/dev/null
    log_success "ffmpeg built successfully."
}

build_mpv() {
    log_header "Build Process: mpv"
    cd "$WORK_DIR"
    rm -rf mpv*
    MPV_FFMPEG_DIR="$WORK_DIR/ffmpeg_staging"
    rm -rf "$MPV_FFMPEG_DIR"
    mkdir -p "$MPV_FFMPEG_DIR"
    log_header "Extracting FFmpeg headers..."
    find "$OUTPUT_DIR" -name "lib*-dev_*.deb" -exec dpkg -x {} "$MPV_FFMPEG_DIR" \;
    MPV_LOCAL_INC="$MPV_FFMPEG_DIR/usr/include"
    MPV_LOCAL_ARCH_INC="$MPV_FFMPEG_DIR/usr/include/aarch64-linux-gnu"
    MPV_LOCAL_LIB="$MPV_FFMPEG_DIR/usr/lib/aarch64-linux-gnu"
    MPV_LOCAL_PKG="$MPV_LOCAL_LIB/pkgconfig"
    run_silent "Fetching mpv source via apt" apt-get source mpv
    MPV_DIR=$(find . -maxdepth 1 -type d -name "mpv-*" | head -n 1)
    cd "$MPV_DIR"
    MPV_PATCH_URL="https://github.com/mpv-player/mpv/compare/master...philipl:mpv:v4l2request.patch"
    run_silent "Downloading mpv v4l2request patch" wget -nv "$MPV_PATCH_URL" -O v4l2-request.patch
    run_silent "Applying mpv v4l2request patch" patch -p1 -N -i v4l2-request.patch
    install_build_deps
    run_silent "Compiling and packaging: mpv" \
    env DEB_CFLAGS_MAINT_PREPEND="-I$MPV_LOCAL_INC -I$MPV_LOCAL_ARCH_INC" \
    DEB_LDFLAGS_MAINT_PREPEND="-L$MPV_LOCAL_LIB" \
    PKG_CONFIG_PATH="$MPV_LOCAL_PKG:$PKG_CONFIG_PATH" \
    dpkg-buildpackage -us -uc -b -j$(nproc)
    mv ../*.deb "$OUTPUT_DIR"/ 2>/dev/null
    rm -rf "$MPV_FFMPEG_DIR"
    log_success "mpv built successfully."
}

build_debian_kernel() {
    log_header "Build Process: Debian Linux Kernel"
    cd "$WORK_DIR"
    unset CFLAGS
    unset CXXFLAGS
    unset LDFLAGS
    export DEB_CFLAGS_APPEND="-mcpu=cortex-a76.cortex-a55 -O2 -pipe"
    export DEB_CXXFLAGS_APPEND="-mcpu=cortex-a76.cortex-a55 -O2 -pipe"
    local KERNEL_DIR="linux-debian"
    local REPO_URL="https://salsa.debian.org/kernel-team/linux.git"
    local BRANCH="debian/latest"
    if [ ! -d "$KERNEL_DIR" ]; then
        run_silent "Cloning Debian kernel repository ($BRANCH)" git clone --single-branch -b "$BRANCH" "$REPO_URL" "$KERNEL_DIR"
    fi
    cd "$KERNEL_DIR"
    cat <<EOF >> debian/config/arm64/config
CONFIG_DRM_ACCEL=y
CONFIG_DRM_ACCEL_ROCKET=m
CONFIG_VIDEO_SYNOPSYS_HDMIRX=m
CONFIG_SND_SOC_ES8328=m
CONFIG_SND_SOC_ES8328_I2C=m
CONFIG_VIDEO_ROCKCHIP_RKVENC=m
EOF
    run_silent "Installing base python modules" apt-get install -y python3-dacite python3-jinja2 perl
    export skipdbg=true
    export DEBIAN_KERNEL_DISABLE_DEBUG=yes
    export DEBIAN_KERNEL_DISABLE_CLOUD=y
    export DEBIAN_KERNEL_DISABLE_RT=y
    export DEBIAN_KERNEL_DISABLE_DOCS=yes
    export DEB_BUILD_OPTIONS="nodoc nocross nosource noautodbgsym noddebs nodebug nocheck noudeb"
    export DEB_BUILD_PROFILES="pkg.linux.nokerneldbg pkg.linux.nokerneldbginfo pkg.linux.nosource nodoc nosource nocloud nort noudeb"
    export MAKEFLAGS="DTC_FLAGS=-@"
    export DTC_FLAGS="-@"
    run_silent "Nuking RT, Cloud, and 16k flavours" perl -0777 -pi -e 's/\[\[flavour\]\]\nname = '\''(cloud-arm64|rt-arm64|arm64-16k)'\''[\s\S]*?(?=\[\[flavour\]\]|\[\[featureset\]\])//g' debian/config/arm64/defines.toml
    run_silent "Nuking Cross-Arch libc-dev configs" perl -0777 -pi -e 's/\[\[kernelarch\]\]\nname = '\''(alpha|arc|arm|parisc|loongarch|m68k|mips|powerpc|riscv|s390|sh|sparc|x86)'\''[\s\S]*?(?=\[\[kernelarch\]\]|\[\[featureset\]\]|\[\[debianrelease\]\])//g' debian/config/defines.toml
    run_silent "Generating debian/control" sh -c "make -f debian/rules debian/control || true"
    run_silent "Installing build dependencies" mk-build-deps --install --remove --tool 'apt-get -y' debian/control
    run_silent "Downloading orig tarball" origtargz
    run_silent "Applying Debian patches (orig)" debian/rules orig
    run_silent "Preparing and patching source" debian/rules source
    log_header "Applying RK3588 Video/Media Patches"
    LORE_MSGIDS=(
        "20260409-rkvdec-multicore-v1-0-62b316abf0f7@collabora.com"
        "20260325-spu-rga3-v4-0-e90ec1c61354@pengutronix.de"
    )
    for msgid in "${LORE_MSGIDS[@]}"; do
        run_silent "Applying patch: $msgid" bash -c "
            rm -rf temp_patch.mbx
            set -e
            b4 am -o temp_patch.mbx \"$msgid\" 2>&1
            if [ -d temp_patch.mbx ]; then
                for p in \$(ls temp_patch.mbx/*.mbx | sort); do
                    patch -p1 --batch -N < \"\$p\" 2>&1
                done
            else
                patch -p1 --batch -N < temp_patch.mbx 2>&1
            fi
            rm -rf temp_patch.mbx
        "
    done
    run_silent "Applying patch: Out-of-tree VEPU580 driver" bash -c "wget -qO- https://github.com/rcawston/rockchip-rk3588-mainline-patches/raw/refs/heads/main/0001-rockchip-rk3588-vepu580-encoder-support-v3.patch | patch -p1 -N"
    log_header "Starting compilation"
    run_silent "Compiling and packaging: Debian Kernel" dpkg-buildpackage -us -uc -b -j$(nproc)
    mv ../*.deb "$OUTPUT_DIR"/ 2>/dev/null
    log_success "Debian Kernel built successfully."
}

prepare_environment

echo "--- Build Run Started: $(date) ---" > "$LOG_FILE"

build_standard_repos
build_debian_kernel
build_ffmpeg
build_mpv

run_silent "Cleaning unnecessary packages" rm -f "$OUTPUT_DIR"/*dbg*.deb "$OUTPUT_DIR"/*-doc*.deb "$OUTPUT_DIR"/*-source*.deb "$OUTPUT_DIR"/*-cross*.deb

log_header "All tasks completed successfully!"
echo -e "${GREEN}Artifacts are located in: $OUTPUT_DIR${NC}"
echo "--- Run Finished: $(date) ---" | tee -a "$LOG_FILE"
