FROM debian:trixie

LABEL maintainer="Halhadus"
LABEL description="Build environment for Rockchip multimedia packages on Debian Trixie"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    debhelper \
    devscripts \
    equivs \
    git \
    libdrm-dev \
    libegl-dev \
    libffi-dev \
    libgbm-dev \
    libgl-dev \
    libssl-dev \
    libstdc++6 \
    libvulkan-dev \
    libwayland-bin \
    libwayland-client0 \
    libwayland-dev \
    libx11-xcb-dev \
    libxcb-dri2-0-dev \
    libxcb-dri3-dev \
    libxcb-glx0-dev \
    libxcb-present-dev \
    libxcb-randr0-dev \
    libxcb-shm0-dev \
    libxcb-sync-dev \
    libxkbcommon-dev \
    meson \
    pkg-config \
    rsync \
    wayland-protocols \
    wget \
    xorg-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /root

COPY scripts/ /root/scripts/

RUN chmod +x /root/scripts/build.sh

CMD ["/root/scripts/build.sh"]
