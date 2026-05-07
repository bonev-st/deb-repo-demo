#!/usr/bin/env bash
# regenerate.sh — generate APT repository indices for one board/yocto-version
#
# Reads .deb packages from work/oss/, work/rz-graphics/, work/rz-codecs/,
# builds a staging tree, generates Packages + Release, and GPG-signs the result.
# The staging tree is then ready for upload by deploy.sh.
#
# Usage:   ./regenerate.sh <board> <yocto-version> [codename]
# Example: ./regenerate.sh vk-d184280e 4.0.1 trixie

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib.sh"

BOARD="${1:-}"
YOCTO="${2:-}"
CODENAME="${3:-trixie}"

if [[ -z "$BOARD" || -z "$YOCTO" ]]; then
    echo "Usage: $0 <board> <yocto-version> [codename]" >&2
    echo "Example: $0 vk-d184280e 4.0.1 trixie" >&2
    exit 1
fi

require_config GPG_KEY_ID
require_cmds gpg apt-ftparchive gzip find
safe_component BOARD "$BOARD"
safe_component YOCTO "$YOCTO"
safe_component CODENAME "$CODENAME"

# ── Paths ────────────────────────────────────────────────────────────────────

STAGING="$STAGING_DIR/$BOARD/$YOCTO"
POOL="$STAGING/pool"
BINARY="$STAGING/dists/$CODENAME/main/binary-arm64"
RELEASE_DIR="$STAGING/dists/$CODENAME"
CONF="$SCRIPT_DIR/apt-repo.conf"

echo "==> Board:        $BOARD"
echo "==> Yocto:        $YOCTO"
echo "==> Codename:     $CODENAME"
echo "==> Staging:      $STAGING"
echo ""

# ── Build staging pool ───────────────────────────────────────────────────────

rm -rf "$POOL"
mkdir -p "$POOL/oss" "$POOL/rz-graphics" "$POOL/rz-codecs" "$BINARY"

copy_debs() {
    local src="$1" dst="$2" label="$3"
    local count=0
    if [[ -d "$src" ]]; then
        while IFS= read -r -d '' f; do
            cp -f "$f" "$dst/"
            count=$((count + 1))
        done < <(find "$src" -maxdepth 1 -name "*.deb" -print0 2>/dev/null)
    fi
    printf "  %-14s → staging/pool/%-12s (%d packages)\n" "$label" "$label/" "$count"
}

echo "==> Copying packages..."
copy_debs "$WORK_DIR/oss"         "$POOL/oss"         "oss"
copy_debs "$WORK_DIR/rz-graphics" "$POOL/rz-graphics" "rz-graphics"
copy_debs "$WORK_DIR/rz-codecs"   "$POOL/rz-codecs"   "rz-codecs"

TOTAL=$(find "$POOL" -type f -name "*.deb" | wc -l)
echo "  Total: $TOTAL packages"
echo ""

# ── Generate Packages index ──────────────────────────────────────────────────

echo "==> Generating Packages index..."
(cd "$STAGING" && apt-ftparchive packages pool > "$BINARY/Packages")
gzip -kf "$BINARY/Packages"

# ── Generate Release ─────────────────────────────────────────────────────────

echo "==> Generating Release..."
(cd "$STAGING" && apt-ftparchive -c "$CONF" \
    -o APT::FTPArchive::Release::Suite="$CODENAME" \
    -o APT::FTPArchive::Release::Codename="$CODENAME" \
    release "dists/$CODENAME" > "$RELEASE_DIR/Release")

# ── GPG sign ─────────────────────────────────────────────────────────────────

echo "==> Signing Release (key: $GPG_KEY_ID)..."

# InRelease — clearsigned (preferred by modern APT)
gpg --default-key "$GPG_KEY_ID" \
    --batch --yes \
    --clearsign \
    -o "$RELEASE_DIR/InRelease" \
    "$RELEASE_DIR/Release"

# Release.gpg — detached armored signature (legacy fallback)
gpg --default-key "$GPG_KEY_ID" \
    --batch --yes \
    --detach-sign --armor \
    -o "$RELEASE_DIR/Release.gpg" \
    "$RELEASE_DIR/Release"

echo ""
echo "==> Staging tree ready:"
find "$STAGING" -not -name "*.deb" | sort | sed "s|$STAGING||"
echo ""
echo "==> Run ./deploy.sh $BOARD $YOCTO to upload to the server."
