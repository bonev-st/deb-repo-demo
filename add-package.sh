#!/usr/bin/env bash
# add-package.sh — copy a .deb into the correct local subdirectory and redeploy
#
# Routing rules (same as update-repo.sh for the Docker repo):
#   mali-* / kernel-module-mali*  →  rz-graphics/
#   libhwcodecs* / uvcs* / kernel-module-uvcs*  →  rz-codecs/
#   everything else  →  oss/
#
# Usage:   ./add-package.sh <board> <yocto-version> <file.deb> [file.deb ...]
# Example: ./add-package.sh vk-d184280e 4.0.1 ~/path/to/kernel-image-*.deb
#          ./add-package.sh vk-d184280e 4.0.1 mali-library_1.2.3_arm64.deb

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib.sh"

BOARD="${1:-}"
YOCTO="${2:-}"
shift 2 2>/dev/null || true

if [[ -z "$BOARD" || -z "$YOCTO" || $# -eq 0 ]]; then
    echo "Usage: $0 <board> <yocto-version> <file.deb> [file.deb ...]" >&2
    exit 1
fi

route_deb() {
    local base; base="$(basename "$1")"
    case "$base" in
        mali-*|kernel-module-mali*)
            echo "$WORK_DIR/rz-graphics" ;;
        libhwcodecs*|uvcs*|kernel-module-uvcs*)
            echo "$WORK_DIR/rz-codecs" ;;
        *)
            echo "$WORK_DIR/oss" ;;
    esac
}

CHANGED=0
for f in "$@"; do
    if [[ ! -f "$f" ]]; then
        echo "SKIP: $f (not found)" >&2
        continue
    fi
    dest="$(route_deb "$f")"
    fname="$(basename "$f")"
    if command -v dpkg-deb &>/dev/null; then
        arch=$(dpkg-deb --field "$f" Architecture 2>/dev/null) || { echo "SKIP: $f (unreadable .deb)" >&2; continue; }
        if [[ "$arch" != "arm64" && "$arch" != "all" ]]; then
            echo "SKIP: $f (wrong architecture: $arch)" >&2
            continue
        fi
    fi
    mkdir -p "$dest"
    cp -v "$f" "$dest/$fname"
    CHANGED=$((CHANGED + 1))
done

if [[ $CHANGED -eq 0 ]]; then
    echo "No files copied." >&2
    exit 1
fi

echo ""
echo "==> $CHANGED package(s) copied. Deploying..."
"$SCRIPT_DIR/deploy.sh" "$BOARD" "$YOCTO"
