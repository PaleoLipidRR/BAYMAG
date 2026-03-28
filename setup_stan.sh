#!/bin/bash
# setup_stan.sh
# Downloads and builds CmdStan. Run this before setup_baymag.m in MATLAB.
# Usage: bash setup_stan.sh [version]
# Example: bash setup_stan.sh 2.36.0

CMDSTAN_VERSION="${1:-2.36.0}"
INSTALL_DIR="$HOME/.cmdstan"
CMDSTAN_DIR="${INSTALL_DIR}/cmdstan-${CMDSTAN_VERSION}"

if [ -d "$CMDSTAN_DIR" ] && [ -f "$CMDSTAN_DIR/bin/stanc" ]; then
    echo "CmdStan ${CMDSTAN_VERSION} already installed at ${CMDSTAN_DIR}"
    exit 0
fi

echo "Installing CmdStan ${CMDSTAN_VERSION} to ${CMDSTAN_DIR} ..."

# Check for required tools
for cmd in wget make g++; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' is required but not found. Please install it first."
        exit 1
    fi
done

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

TARBALL="cmdstan-${CMDSTAN_VERSION}.tar.gz"
URL="https://github.com/stan-dev/cmdstan/releases/download/v${CMDSTAN_VERSION}/${TARBALL}"

echo "Downloading ${URL} ..."
wget -q --show-progress "$URL" -O "$TARBALL"

echo "Extracting ..."
tar -xzf "$TARBALL"
rm "$TARBALL"

echo "Building CmdStan (this may take a few minutes) ..."
cd "cmdstan-${CMDSTAN_VERSION}" || exit 1
make build -j"$(nproc 2>/dev/null || echo 2)"

echo ""
echo "CmdStan ${CMDSTAN_VERSION} installed at: ${CMDSTAN_DIR}"
echo "Next step: open MATLAB in the BAYMAG directory and run setup_baymag.m"
