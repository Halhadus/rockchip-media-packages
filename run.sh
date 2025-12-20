#!/bin/bash

set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="rockchip-trixie-builder"
OUTPUT_DIR="$BASE_DIR/output"

echo "=== Rockchip Unofficial Package Builder ==="
echo "Workdir: $BASE_DIR"

if ! command -v docker &> /dev/null; then
    echo "Error: Docker could not be found. Please install Docker first."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Building Docker image ($IMAGE_NAME)..."
docker build -t "$IMAGE_NAME" "$BASE_DIR"

echo "Starting build container..."
docker run --rm \
    -v "$BASE_DIR/output:/root/output" \
    -v "$BASE_DIR/build_workspace:/root/build_workspace" \
    "$IMAGE_NAME"

echo "=== Build Process Finished ==="
echo "Check $OUTPUT_DIR for the generated .deb files."
