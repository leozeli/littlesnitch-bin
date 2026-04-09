#!/usr/bin/env bash
# update.sh — Detect new Little Snitch for Linux releases and update PKGBUILD
set -euo pipefail

DOWNLOAD_PAGE="https://obdev.at/products/littlesnitch-linux/download.html"
HASH_URL_TEMPLATE="https://obdev.at/downloads/littlesnitch-linux/littlesnitch-VERSION.hashes.txt"
PKGBUILD="PKGBUILD"

# --- 1. Get current version from PKGBUILD ---
current_ver=$(grep -oP '^pkgver=\K.*' "$PKGBUILD")
echo "Current PKGBUILD version: $current_ver"

# --- 2. Scrape latest version from download page ---
# The download page contains URLs like littlesnitch-X.Y.Z-1-x86_64.pkg.tar.zst
latest_ver=$(curl -sL "$DOWNLOAD_PAGE" \
  | grep -oP 'littlesnitch-\K[0-9]+\.[0-9]+\.[0-9]+(?=-[0-9]+-x86_64\.pkg\.tar\.zst)' \
  | head -1)

if [[ -z "$latest_ver" ]]; then
  echo "ERROR: Could not detect latest version from download page"
  exit 1
fi

echo "Latest upstream version: $latest_ver"

# --- 3. Compare ---
if [[ "$current_ver" == "$latest_ver" ]]; then
  echo "Already up to date. Nothing to do."
  exit 0
fi

echo "New version detected: $current_ver → $latest_ver"

# --- 4. Download new hashes ---
hash_url="${HASH_URL_TEMPLATE/VERSION/$latest_ver}"
echo "Fetching hashes from: $hash_url"
hashes=$(curl -sL "$hash_url")

if [[ -z "$hashes" ]]; then
  echo "ERROR: Could not download hashes file"
  exit 1
fi

# Extract SHA256 for each arch
sha_x86_64=$(echo "$hashes" | grep -oP '^[0-9a-f]+(?=\s+littlesnitch-.*-x86_64\.pkg\.tar\.zst)')
sha_aarch64=$(echo "$hashes" | grep -oP '^[0-9a-f]+(?=\s+littlesnitch-.*-aarch64\.pkg\.tar\.zst)')
sha_riscv64=$(echo "$hashes" | grep -oP '^[0-9a-f]+(?=\s+littlesnitch-.*-riscv64\.pkg\.tar\.zst)')

if [[ -z "$sha_x86_64" || -z "$sha_aarch64" || -z "$sha_riscv64" ]]; then
  echo "ERROR: Could not extract all checksums"
  echo "  x86_64:  ${sha_x86_64:-MISSING}"
  echo "  aarch64: ${sha_aarch64:-MISSING}"
  echo "  riscv64: ${sha_riscv64:-MISSING}"
  exit 1
fi

echo "Checksums:"
echo "  x86_64:  $sha_x86_64"
echo "  aarch64: $sha_aarch64"
echo "  riscv64: $sha_riscv64"

# --- 5. Update PKGBUILD ---
sed -i "s/^pkgver=.*/pkgver=$latest_ver/" "$PKGBUILD"
sed -i "s/^sha256sums_x86_64=.*/sha256sums_x86_64=('$sha_x86_64')/" "$PKGBUILD"
sed -i "s/^sha256sums_aarch64=.*/sha256sums_aarch64=('$sha_aarch64')/" "$PKGBUILD"
sed -i "s/^sha256sums_riscv64=.*/sha256sums_riscv64=('$sha_riscv64')/" "$PKGBUILD"

echo "PKGBUILD updated to $latest_ver"

# --- 6. Regenerate .SRCINFO ---
# In CI this runs inside an Arch container; locally needs makepkg
if command -v makepkg &>/dev/null; then
  makepkg --printsrcinfo > .SRCINFO
  echo ".SRCINFO regenerated"
else
  echo "WARNING: makepkg not available, .SRCINFO not regenerated (will be done in CI container)"
fi

echo "UPDATE_VERSION=$latest_ver" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "Done."
