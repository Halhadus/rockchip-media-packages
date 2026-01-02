#!/bin/bash

set -e

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="pipwire-aac-builder"
DOCKERFILE="Dockerfile.pipewireaac"
OUTPUT_DIR="$BASE_DIR/output"
WORKSPACE_DIR="$BASE_DIR/build_workspace"

echo "=== Pipewire AAC Builder Started ==="
echo "Workdir: $BASE_DIR"

if ! command -v docker &> /dev/null; then
    echo "Error: Docker could not be found."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORKSPACE_DIR"

echo "Building Docker image ($IMAGE_NAME)..."
docker build --platform linux/arm64 -f "$BASE_DIR/$DOCKERFILE" -t "$IMAGE_NAME" "$BASE_DIR"

echo "Starting build container (ARM64)..."
docker run --rm \
    --platform linux/arm64 \
    --privileged \
    -v "$OUTPUT_DIR:/root/output" \
    -v "$WORKSPACE_DIR:/root/build_workspace" \
    "$IMAGE_NAME"

echo "=== Build Process Finished ==="
echo "Check $OUTPUT_DIR for the generated packages."
