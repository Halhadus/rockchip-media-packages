#!/bin/bash

set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="rockchip-firefox-cross-builder"
DOCKERFILE="Dockerfile.firefox"
OUTPUT_DIR="$BASE_DIR/output"
WORKSPACE_DIR="$BASE_DIR/build_workspace"

echo "=== Firefox MPP Cross-Builder Started ==="
echo "Workdir: $BASE_DIR"
echo "Dockerfile: $DOCKERFILE"

if ! command -v docker &> /dev/null; then
    echo "Error: Docker could not be found. Please install Docker first."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORKSPACE_DIR"

echo "Installing QEMU binfmt support..."
docker run --privileged --rm tonistiigi/binfmt --install all

echo "Building Docker image ($IMAGE_NAME)..."
docker build -f "$BASE_DIR/$DOCKERFILE" -t "$IMAGE_NAME" "$BASE_DIR"

echo "Starting build container..."
docker run --rm \
    --platform linux/amd64 \
    -v "$OUTPUT_DIR:/root/output" \
    -v "$WORKSPACE_DIR:/root/build_workspace" \
    "$IMAGE_NAME"

echo "=== Build Process Finished ==="
echo "Check $OUTPUT_DIR for the generated packages."
