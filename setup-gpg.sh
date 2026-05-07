#!/usr/bin/env bash
# setup-gpg.sh — one-time GPG key generation for APT repository signing
#
# Run this once on the dev host before the first deploy.
# The private key stays in the local GPG keyring and never leaves this machine.
# The exported public key (....-repo-public.gpg) is uploaded to the server by deploy.sh.
#
# After running this script, copy the printed key fingerprint into config.sh → GPG_KEY_ID.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib.sh"

require_config GPG_KEY_EMAIL PUBKEY_NAME
require_cmds gpg

# ── If the key already exists, just export it ────────────────────────────────

if gpg --list-keys "$GPG_KEY_EMAIL" &>/dev/null; then
    echo "GPG key for '$GPG_KEY_EMAIL' already exists:"
    gpg --list-keys "$GPG_KEY_EMAIL"
    echo ""
    echo "Exporting public key to: $PUBKEY_FILE"
    gpg --armor --export "$GPG_KEY_EMAIL" > "$PUBKEY_FILE"
    echo ""
    KEY_ID=$(gpg --list-keys --with-colons "$GPG_KEY_EMAIL" \
        | awk -F: '/^fpr:/{print $10; exit}')
    echo "Key fingerprint: $KEY_ID"
    echo ""
    echo "Set this in config.sh:"
    echo "  GPG_KEY_ID=\"$KEY_ID\""
    exit 0
fi

# ── Generate a new 4096-bit RSA key ─────────────────────────────────────────

echo "Generating GPG key for: Renesas APT Repository <$GPG_KEY_EMAIL>"
echo ""

gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: Renesas APT Repository
Name-Email: $GPG_KEY_EMAIL
Expire-Date: 0
# The key is generated without a passphrase for unattended signing.
# Keep the private key secure — anyone who obtains it can sign packages.
%no-protection
EOF

echo ""
echo "Key generated:"
gpg --list-keys "$GPG_KEY_EMAIL"

KEY_ID=$(gpg --list-keys --with-colons "$GPG_KEY_EMAIL" \
    | awk -F: '/^fpr:/{print $10; exit}')

echo ""
echo "Exporting public key to: $PUBKEY_FILE"
gpg --armor --export "$GPG_KEY_EMAIL" > "$PUBKEY_FILE"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " NEXT STEPS"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo " 1. Set GPG_KEY_ID in config.sh:"
echo "      GPG_KEY_ID=\"$KEY_ID\""
echo ""
echo " 2. Back up your private key to a secure offline location:"
echo "      gpg --armor --export-secret-keys $GPG_KEY_EMAIL \\"
echo "        > $PUBKEY_NAME-PRIVATE-KEY-KEEP-SAFE.gpg"
echo "    Store this file encrypted and off this machine."
echo ""
echo " 3. Run ./deploy.sh to publish the first repository."
echo "════════════════════════════════════════════════════════════════"
