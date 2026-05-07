# Renesas APT Repository

Public Debian APT repository for Renesas RZ/G2LC board-specific packages,
hosted at **https://apt.example.com**.

---

## Repository Layout

```
https://apt.example.com/
├── repo-public.gpg              ← GPG public key for clients to import
├── {board}/
│   └── {yocto-version}/         ← APT repository root (dists/ + pool/ here)
│       ├── pool/
│       │   ├── oss/             ← kernel, device trees, MMNGR, VSPM, GStreamer
│       │   ├── rz-graphics/     ← Mali GPU driver and libraries
│       │   └── rz-codecs/       ← optional proprietary codec packages
│       └── dists/
│           └── trixie/
│               ├── Release
│               ├── Release.gpg
│               ├── InRelease
│               └── main/
│                   └── binary-arm64/
│                       ├── Packages
│                       └── Packages.gz
```

**First repository:**
- Board: `vk-d184280e`
- Yocto: `4.0.1`
- URL: `https://apt.example.com/vk-d184280e/4.0.1`

---

## Scripts

| Script | Purpose |
|---|---|
| `setup-gpg.sh` | One-time: generate GPG signing key |
| `config.sh` | Shared server + GPG configuration |
| `regenerate.sh` | Build APT indices locally from work/{oss,rz-graphics,rz-codecs} |
| `deploy.sh` | Regenerate + rsync to server |
| `add-package.sh` | Add/update a .deb file then deploy |
| `apt-repo.conf` | apt-ftparchive Release metadata |

---

## Prerequisites

On the Ubuntu dev host:

```bash
sudo apt install apt-utils rsync
```

SSH key must be configured for the server (passwordless login):

```bash
ssh-copy-id -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST
```

---

## One-Time Server Setup

### 1. Create the subdomain

Log in to your hosting control panel → **Subdomains** → create `apt.example.com`.
The panel creates `~/apt.example.com/` as the document root.

### 2. Enable HTTPS (optional but recommended)

Your hosting control panel → **SSL/TLS** → **Let's Encrypt** → issue certificate for `apt.example.com`.

### 3. Generate GPG signing key

Run once on the dev host:

```bash
cd publish/
./setup-gpg.sh
```

Copy the printed key fingerprint into `config.sh` → `GPG_KEY_ID`.

**Back up the private key immediately:**

```bash
gpg --armor --export-secret-keys repo@example.com > myserver-repo-PRIVATE-KEY-KEEP-SAFE.gpg
```

Store this file encrypted and offline. Without it, you cannot sign future releases.

### 4. Fill in config.sh

Edit `publish/config.sh` and set:
- `REMOTE_HOST` — SSH hostname of your server
- `REMOTE_USER` — your SSH username
- `REMOTE_PORT` — SSH port
- `GPG_KEY_ID` — fingerprint printed by `setup-gpg.sh`

### 5. First deployment

```bash
cd publish/
./deploy.sh vk-d184280e 4.0.1
```

This builds the staging tree, signs the Release, and uploads everything to the server.

### 6. Verify

```bash
curl https://apt.example.com/vk-d184280e/4.0.1/dists/trixie/Release
curl https://apt.example.com/repo-public.gpg
```

---

## Adding or Updating Packages

### Add one or more .deb files

```bash
./add-package.sh vk-d184280e 4.0.1 /path/to/kernel-image-*.deb
./add-package.sh vk-d184280e 4.0.1 /path/to/mali-library_*.deb
```

The script routes each file automatically:

| Package name pattern | Destination |
|---|---|
| `mali-*`, `kernel-module-mali*` | `work/rz-graphics/` |
| `libhwcodecs*`, `uvcs*`, `kernel-module-uvcs*` | `work/rz-codecs/` |
| everything else | `work/oss/` |

### Update the repository without adding new packages

If you only want to re-sign or update the metadata:

```bash
./deploy.sh vk-d184280e 4.0.1
```

---

## Adding a New Board or Yocto Version

The repository structure is self-contained per `{board}/{yocto-version}/`.
No central configuration needs to change.

### New Yocto version for the same board

1. Sync the new packages into `work/oss/`, `work/rz-graphics/`, `work/rz-codecs/`
   (using `sync-from-yocto.sh` or manually).
2. Deploy:
   ```bash
   ./deploy.sh vk-d184280e 4.1.0
   ```

### New board

```bash
./deploy.sh rz-g2lc-smarc 5.0.0
```

Clients for this board add:
```
deb [arch=arm64 signed-by=/etc/apt/keyrings/myserver-repo.gpg] \
    https://apt.example.com/rz-g2lc-smarc/5.0.0 trixie main
```

---

## Client APT Configuration

Run the following on each target board (arm64, as root or with sudo):

```bash
# 1. Import the repository signing key
curl -fsSL https://apt.x-cas.eu/repo-public.gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/xcas-repo.gpg

# 2. Add the APT source
echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/xcas-repo.gpg] \
  https://apt.x-cas.eu/vk-d184280e/4.0.1 trixie main" \
  | sudo tee /etc/apt/sources.list.d/renesas-custom.list

# 3. Pin Renesas packages so they always win over Debian packages
sudo tee /etc/apt/preferences.d/renesas-pin <<'EOF'
Package: kernel-image-* kernel-module-* devicetree libmmngr* libmmngrbuf* libvspm* mali-* gstreamer1.0 libgstallocators-1.0-0 libgstvideo-1.0-0 gstreamer1.0-omx* gstreamer1.0-plugin-vspmfilter*
Pin: release l=renesas-custom
Pin-Priority: 1001
EOF

# 4. Update and install
sudo apt update
sudo apt install \
    kernel-image-6.1.141-cip43-yocto-standard \
    kernel-module-mmngr kernel-module-mmngrbuf \
    kernel-module-vspm kernel-module-vspmif \
    libmmngr1 libmmngrbuf1 libvspm1 \
    kernel-module-mali mali-library mali-gles mali-opencl \
    gstreamer1.0-plugin-vspmfilter devicetree
```

### Why priority 1001?

APT priorities above 1000 cause a package to be installed even if it means
downgrading an already-installed package. Renesas kernel and driver packages
must take precedence over any identically-named Debian packages, so 1001 is
the correct value. Do not lower it to 900 or 500 — those values only prefer
the package when no other version is installed.

### What the pin covers

| Pattern | Packages |
|---|---|
| `kernel-image-*` | Renesas/Yocto kernel image |
| `kernel-module-*` | mmngr, mmngrbuf, vspm, vspmif, Mali |
| `devicetree` | Board device tree blobs |
| `libmmngr*`, `libmmngrbuf*`, `libvspm*` | Memory manager and VSP userspace libs |
| `mali-*` | Mali GPU userspace (library, GLES, OpenCL) |
| `gstreamer1.0-plugin-vspmfilter` | VSP-accelerated GStreamer filter |

---

## GPG Key Management

### Rotate the signing key

1. Generate a new key: `./setup-gpg.sh` (after deleting the old one from keyring, or use a different email)
2. Update `GPG_KEY_ID` in `config.sh`
3. Re-deploy all repositories (Release files need to be re-signed):
   ```bash
   ./deploy.sh vk-d184280e 4.0.1
   ```
4. Clients must re-import the new public key from `https://apt.example.com/repo-public.gpg`

### Key backup and restore

```bash
# Backup
gpg --armor --export-secret-keys repo@example.com > private-key.gpg

# Restore on a new machine
gpg --import private-key.gpg
gpg --import myserver-repo-public.gpg
```

---

## Recovery: Interrupted or Partial Upload

If `deploy.sh` is interrupted mid-transfer, simply re-run it:

```bash
./deploy.sh vk-d184280e 4.0.1
```

`rsync --delete` ensures the server matches the local staging tree exactly.

If the staging directory is stale or corrupt, delete it and regenerate:

```bash
rm -rf publish/staging/vk-d184280e/4.0.1
./deploy.sh vk-d184280e 4.0.1
```

---

## Backup Recommendations

| Item | Backup needed? | Notes |
|---|---|---|
| `work/oss/*.deb` | Yes — source of truth | Packages cannot be regenerated |
| `work/rz-graphics/*.deb` | Yes | Same |
| `work/rz-codecs/*.deb` | Yes | Same |
| `publish/staging/` | No | Fully regenerable by `regenerate.sh` |
| GPG private key | **Critical** | Loss = cannot sign new releases |
| GPG public key | Low priority | Re-exportable from keyring anytime |
| Server files | Low priority | Fully regenerable from local packages + scripts |

The packages in `work/oss/`, `work/rz-graphics/`, and `work/rz-codecs/` are the only
irreplaceable artifacts. Back them up alongside the GPG private key.
