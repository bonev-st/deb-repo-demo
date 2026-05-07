#!/usr/bin/env bash
# deploy.sh — regenerate APT indices and sync the repository to the server
#
# Usage:   ./deploy.sh <board> <yocto-version> [codename]
# Example: ./deploy.sh vk-d184280e 4.0.1 trixie

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib.sh"

BOARD="${1:-}"
YOCTO="${2:-}"
CODENAME="${3:-trixie}"

if [[ -z "$BOARD" || -z "$YOCTO" ]]; then
    echo "Usage: $0 <board> <yocto-version> [codename]" >&2
    exit 1
fi

require_config REMOTE_HOST REMOTE_USER REMOTE_PORT REMOTE_BASE
require_cmds ssh rsync
safe_component BOARD "$BOARD"
safe_component YOCTO "$YOCTO"
safe_component CODENAME "$CODENAME"

STAGING="$STAGING_DIR/$BOARD/$YOCTO"
SSH_OPTS="-p $REMOTE_PORT -o LogLevel=ERROR"
RSYNC_SSH="ssh $SSH_OPTS"
REMOTE="$REMOTE_USER@$REMOTE_HOST"

# ── Step 1: Regenerate indices ───────────────────────────────────────────────

echo "==> Regenerating APT indices..."
"$SCRIPT_DIR/regenerate.sh" "$BOARD" "$YOCTO" "$CODENAME"

# ── Step 2: Create remote directory structure ────────────────────────────────
# ssh mkdir -p ensures all parent dirs exist before rsync tries to write into them.

echo "==> Creating remote directories..."
ssh $SSH_OPTS "$REMOTE" \
    "mkdir -p '$REMOTE_BASE/$BOARD/$YOCTO'"

# ── Step 3: Upload public key to repo root (idempotent) ──────────────────────

if [[ -f "$PUBKEY_FILE" ]]; then
    echo "==> Uploading public key → $REMOTE_BASE/repo-public.gpg"
    rsync -az -e "$RSYNC_SSH" \
        "$PUBKEY_FILE" \
        "$REMOTE:$REMOTE_BASE/repo-public.gpg"
else
    echo "WARNING: Public key not found at $PUBKEY_FILE" >&2
    echo "  Run ./setup-gpg.sh first." >&2
fi

# ── Step 4: Upload .htaccess to repo root (idempotent) ───────────────────────

if [[ -f "$SCRIPT_DIR/.htaccess" ]]; then
    echo "==> Uploading .htaccess → $REMOTE_BASE/.htaccess"
    rsync -az -e "$RSYNC_SSH" \
        "$SCRIPT_DIR/.htaccess" \
        "$REMOTE:$REMOTE_BASE/.htaccess"
fi

# ── Step 5: Sync staging tree to server ─────────────────────────────────────
# --delete removes files on the server that no longer exist locally.
# This keeps the server in sync when packages are removed or renamed.

echo "==> Syncing $BOARD/$YOCTO → server..."
rsync -avz --delete \
    -e "$RSYNC_SSH" \
    "$STAGING/" \
    "$REMOTE:$REMOTE_BASE/$BOARD/$YOCTO/"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Deployment complete."
echo " https://$REMOTE_BASE/$BOARD/$YOCTO/dists/$CODENAME/Release"
echo "════════════════════════════════════════════════════════════════"
