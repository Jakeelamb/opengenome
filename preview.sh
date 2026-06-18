#!/bin/bash

# Script to generate preview.gif locally using VHS
# Requirements: vhs, ffmpeg, ttyd, and JetBrains Mono font

set -e

# Check if VHS is installed
if ! command -v vhs &> /dev/null; then
    echo "Error: VHS is not installed"
    echo "Install it with: go install github.com/charmbracelet/vhs@latest"
    exit 1
fi

# Check if Open Genome binary exists
if ! command -v opengenome &> /dev/null && [ ! -f "./build/opengenome" ] && [ ! -f "./target/release/opengenome" ]; then
    echo "Error: opengenome binary not found"
    echo "Build it first with: cargo build --release"
    exit 1
fi

# Add Open Genome to PATH if needed
if [ -f "./target/release/opengenome" ]; then
    export PATH="$PWD/target/release:$PATH"
elif [ -f "./build/opengenome" ]; then
    export PATH="$PWD/build:$PATH"
fi

echo "Generating preview.gif..."
cd .github
vhs preview.tape

echo "✓ Preview generated successfully at .github/preview.gif"
