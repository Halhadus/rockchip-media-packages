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
        "https://github.com/Halhadus/debian-opi5plus-halhadus-config main debian-opi5plus-halhadus-config"
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
    log_header "Installing Collabora Kernel api headers..."
    LIBC_DEV_PKG=$(find "$OUTPUT_DIR" -name "linux-libc-dev_*.deb" | head -n 1)
    if [ -f "$LIBC_DEV_PKG" ]; then
        run_silent "Installing $LIBC_DEV_PKG" dpkg -i "$LIBC_DEV_PKG"
    else
        log_error "linux-libc-dev package not found!"
        exit 1
    fi
    run_silent "Fetching ffmpeg source via apt" apt-get source ffmpeg
    FFMPEG_DIR=$(find . -maxdepth 1 -type d -name "ffmpeg-*" | head -n 1)
    cd "$FFMPEG_DIR"
    #run_silent "Downloading v4l2request.diff" wget -nv "https://code.ffmpeg.org/FFmpeg/FFmpeg/compare/master...Kwiboo:v4l2request-2025-v3-rkvdec.diff" -O v4l2request.diff
    run_silent "Downloading v4l2request.diff" wget -nv "https://code.ffmpeg.org/FFmpeg/FFmpeg/compare/86eb07154d0255a5e96c822d8dc7805ade600f0b...Kwiboo:v4l2request-2025-v3-rkvdec.diff" -O v4l2request.diff
    run_silent "Downloading strps1.patch" wget -nv "https://gitlab.collabora.com/detlev/ffmpeg/-/commit/20b37c99b9318e1b104aa11f2569fcb0c7387e1e.patch" -O strps1.patch
    run_silent "Downloading strps2.patch" wget -nv "https://gitlab.collabora.com/detlev/ffmpeg/-/commit/dfa10f6e10441aef0d8b45c97bf3bce6598ede48.patch" -O strps2.patch
    filterdiff -x '*/Changelog' -x '*/.forgejo/CODEOWNERS' v4l2request.diff > clean_v4l2request.diff
    run_silent "Applying clean_v4l2request.diff" patch -p1 -i clean_v4l2request.diff
    run_silent "Applying strps1.patch" git apply --ignore-whitespace --ignore-space-change strps1.patch
    run_silent "Applying strps2.patch" git apply --ignore-whitespace --ignore-space-change strps2.patch
    echo -e "${YELLOW}-> Modifying debian/rules flags (enable v4l2-request/m2m)...${NC}"
    sed -i '/--enable-libvpx/a \                --enable-v4l2-request \\\n                --enable-libudev \\\n                --enable-v4l2_m2m \\\n                --enable-libdrm \\\n                --enable-neon \\\n                --enable-hwaccels \\' debian/rules
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

build_collabora_kernel() {
    log_header "Build Process: Linux Kernel (Collabora rockchip-devel)"
    cd "$WORK_DIR"
    local KERNEL_DIR="linux-collabora"
    local REPO_URL="https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux.git"
    local BRANCH="rockchip-devel"
    if [ ! -d "$KERNEL_DIR" ]; then
        run_silent "Cloning kernel repository ($BRANCH)" git clone --single-branch -b "$BRANCH" "$REPO_URL" "$KERNEL_DIR"
    fi
    cd "$KERNEL_DIR"
    run_silent "Installing kernel build dependencies" apt-get install -y -qq build-essential libncurses-dev bison flex libssl-dev libelf-dev bc cpio rsync dwarves kmod fakeroot debhelper dpkg-dev python3-dev libdw-dev lsb-release
    run_silent "Patching DTS for PWM12" sed -i '/pwm@febf0000 {/,/};/ s/status = "disabled";/status = "okay";/' arch/arm64/boot/dts/rockchip/rk3588-base.dtsi
    run_silent "Patching DTS for resolve RTC Interrupt Storm problem" sed -i '/&hym8563 {/,/};/ s/IRQ_TYPE_LEVEL_LOW/IRQ_TYPE_EDGE_FALLING/' arch/arm64/boot/dts/rockchip/rk3588-orangepi-5-plus.dts
    cat <<EOF > custom_kernel.config
CONFIG_DEVFREQ_GOV_PERFORMANCE=y
CONFIG_DEVFREQ_GOV_POWERSAVE=y
CONFIG_PWM_ROCKCHIP=y
CONFIG_ZRAM=m
CONFIG_ZSMALLOC=y
CONFIG_ZSTD_COMPRESS=y
CONFIG_CRYPTO_ZSTD=y
CONFIG_ZRAM_BACKEND_ZSTD=y
CONFIG_SECURITY_LANDLOCK=y
CONFIG_DRM_ACCEL_ROCKET=m
CONFIG_DRM_ACCEL=y
CONFIG_WIREGUARD=m
CONFIG_LRU_GEN=y
CONFIG_LRU_GEN_ENABLED=y
CONFIG_PREEMPT=y
CONFIG_TCP_CONG_BBR=y
CONFIG_DEFAULT_TCP_CONG="bbr"
CONFIG_PSI=y
CONFIG_PSI_DEFAULT_DISABLED=n
CONFIG_BT_LE=y
CONFIG_BT_RFCOMM=m
CONFIG_BT_RFCOMM_TTY=y
CONFIG_BT_HCIUART_RTL=y
CONFIG_BT_BNEP=m
CONFIG_BT_BNEP_MC_FILTER=y
CONFIG_BT_BNEP_PROTO_FILTER=y
CONFIG_RTW89=m
CONFIG_RTW89_CORE=m
CONFIG_RTW89_PCI=m
CONFIG_RTW89_8852BE=m
CONFIG_HID_BATTERY_STRENGTH=y
CONFIG_HIDRAW=y
CONFIG_UHID=m
CONFIG_INPUT_UINPUT=m
CONFIG_CRYPTO_USER_API_HASH=m
CONFIG_CRYPTO_USER_API_SKCIPHER=m
CONFIG_CRYPTO_USER_API_AEAD=m
CONFIG_BT_AOSPEXT=y
CONFIG_DEBUG_INFO_NONE=y
CONFIG_NETFILTER=y
CONFIG_NETFILTER_ADVANCED=y
CONFIG_NF_CONNTRACK=m
CONFIG_NETFILTER_XTABLES=m
CONFIG_NETFILTER_XT_NAT=m
CONFIG_NETFILTER_XT_MARK=m
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=m
CONFIG_NETFILTER_XT_MATCH_CONNTRACK=m
CONFIG_NETFILTER_XT_MATCH_IPVS=m
CONFIG_IP_NF_IPTABLES=m
CONFIG_IP_NF_FILTER=m
CONFIG_IP_NF_NAT=m
CONFIG_IP_NF_TARGET_MASQUERADE=m
CONFIG_IP_NF_MANGLE=m
CONFIG_IP_NF_RAW=m
CONFIG_NF_NAT=m
CONFIG_IP6_NF_IPTABLES=m
CONFIG_IP6_NF_FILTER=m
CONFIG_IP6_NF_NAT=m
CONFIG_IP6_NF_MANGLE=m
CONFIG_IP6_NF_RAW=m
CONFIG_IP6_NF_TARGET_MASQUERADE=m
CONFIG_NF_TABLES=m
CONFIG_NF_TABLES_INET=y
CONFIG_NFT_COMPAT=m
CONFIG_NFT_CT=m
CONFIG_NFT_FIB=m
CONFIG_NFT_FIB_IPV4=m
CONFIG_NFT_FIB_IPV6=m
CONFIG_NFT_MASQ=m
CONFIG_NFT_NAT=m
CONFIG_BRIDGE=m
CONFIG_BRIDGE_NETFILTER=m
CONFIG_VETH=m
CONFIG_MACVLAN=m
CONFIG_DUMMY=m
CONFIG_VXLAN=m
CONFIG_IP_VS=m
CONFIG_IP_VS_NFCT=y
CONFIG_IP_VS_PROTO_TCP=y
CONFIG_IP_VS_PROTO_UDP=y
CONFIG_IP_VS_RR=m
CONFIG_BLK_DEV_THROTTLING=y
CONFIG_NET_CLS_CGROUP=m
CONFIG_CGROUP_NET_PRIO=y
CONFIG_CFS_BANDWIDTH=y
EOF
    run_silent "Merging defconfig with custom config" env ARCH=arm64 scripts/kconfig/merge_config.sh -m arch/arm64/configs/defconfig custom_kernel.config
    run_silent "Applying olddefconfig" make ARCH=arm64 olddefconfig
    rm -f ../linux-*.deb ../linux-*.buildinfo ../linux-*.changes
    run_silent "Hiding DTS changes from Git status" git update-index --assume-unchanged arch/arm64/boot/dts/rockchip/rk3588-base.dtsi
    run_silent "Hiding DTS changes from Git status" git update-index --assume-unchanged arch/arm64/boot/dts/rockchip/rk3588-orangepi-5-plus.dts
    run_silent "Hiding config changes from Git status" git update-index --assume-unchanged arch/arm64/configs/defconfig
    export KCFLAGS="-march=armv8.2-a -mtune=cortex-a76.cortex-a55"
    run_silent "Compiling and packaging: Linux Kernel" make DTC_FLAGS="-@" bindeb-pkg -j$(nproc) ARCH=arm64
    log_header "Creating Meta Packages"
    IMAGE_DEB=$(ls ../linux-image*.deb | head -n 1 2>/dev/null)
    if [ -f "$IMAGE_DEB" ]; then
        ACTUAL_PKG_NAME=$(dpkg-deb -f "$IMAGE_DEB" Package)
        PKG_VERSION=$(dpkg-deb -f "$IMAGE_DEB" Version)
        mkdir -p meta-pkg-img/DEBIAN
        cat <<EOF > meta-pkg-img/DEBIAN/control
Package: linux-image-collabora
Version: ${PKG_VERSION}
Architecture: arm64
Maintainer: Custom Build Script
Description: Meta-package for Collabora kernel image
Depends: ${ACTUAL_PKG_NAME}
EOF
        run_silent "Building meta-package: linux-image-collabora" dpkg-deb --build meta-pkg-img "../linux-image-collabora_${PKG_VERSION}_arm64.deb"
        rm -rf meta-pkg-img
    fi
    HEADERS_DEB=$(ls ../linux-headers*.deb | head -n 1 2>/dev/null)
    if [ -f "$HEADERS_DEB" ]; then
        ACTUAL_HDR_NAME=$(dpkg-deb -f "$HEADERS_DEB" Package)
        HDR_VERSION=$(dpkg-deb -f "$HEADERS_DEB" Version)
        mkdir -p meta-pkg-hdr/DEBIAN
        cat <<EOF > meta-pkg-hdr/DEBIAN/control
Package: linux-headers-collabora
Version: ${HDR_VERSION}
Architecture: arm64
Maintainer: Custom Build Script
Description: Meta-package for Collabora kernel headers
Depends: ${ACTUAL_HDR_NAME}
EOF
        run_silent "Building meta-package: linux-headers-collabora" dpkg-deb --build meta-pkg-hdr "../linux-headers-collabora_${HDR_VERSION}_arm64.deb"
        rm -rf meta-pkg-hdr
    fi
    mv ../linux-*.deb "$OUTPUT_DIR"/ 2>/dev/null
    log_success "Collabora Linux Kernel built successfully."
}

prepare_environment

echo "--- Build Run Started: $(date) ---" > "$LOG_FILE"

build_collabora_kernel
build_ffmpeg
build_mpv
#build_standard_repos

run_silent "Removing debug packages" rm -f "$OUTPUT_DIR"/*dbg*.deb

log_header "All tasks completed successfully!"
echo -e "${GREEN}Artifacts are located in: $OUTPUT_DIR${NC}"
echo "--- Run Finished: $(date) ---" | tee -a "$LOG_FILE"
