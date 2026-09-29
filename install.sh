#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Google Antigravity Local Web GUI - Automated Installer for Termux
# ==============================================================================
set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
BIN_DIR="${PREFIX}/bin"

# Determine script directory safely (handles direct execution and pipe through curl)
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR=""
fi

echo "======================================================"
echo "    Starting Antigravity Local Web GUI Installation   "
echo "======================================================"

# ==============================================================================
# [1/7] Android Storage Permission Setup
# ==============================================================================
# Ensures Termux has access to device storage so local workspaces,
# files, and projects can be accessed without permission errors.
echo "[1/7] Checking Android storage permissions..."
if [ ! -d "$HOME/storage" ]; then
    echo "      Requesting storage permission from Android..."
    termux-setup-storage
    sleep 2
else
    echo "      Storage access already granted."
fi

# ==============================================================================
# [2/7] Glibc Runtime & Package Prerequisites
# ==============================================================================
# Installs glibc-repo, glibc-runner, and python (required for binary patching).
echo "[2/7] Installing glibc and runtime dependencies..."
pkg install glibc-repo -y
pkg install glibc-runner -y
pkg install python -y

# ==============================================================================
# [3/7] Install Antigravity CLI (Upstream wallentx Installer)
# ==============================================================================
# Runs the installer from the wallentx repository to fetch the pre-patched
# Antigravity CLI binary. Credit: https://github.com/wallentx/antigravity-cli-termux
echo "[3/7] Installing Antigravity CLI from upstream repository..."
echo "      Upstream project: https://github.com/wallentx/antigravity-cli-termux by @wallentx"
export AGY_INSTALL_SKIP_LAUNCH=1
curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash

# Verify agy installation succeeded
if ! command -v agy >/dev/null 2>&1 && [ ! -f "$BIN_DIR/agy" ]; then
    echo "[-] Error: 'agy' was not found in $BIN_DIR after installation."
    exit 1
fi

# ==============================================================================
# [4/7] Network & Fast DNS Configuration (Fix IPv6 Latency)
# ==============================================================================
# Mobile networks often cause slow IPv6 DNS lookups in Termux, resulting in
# a delay during startup. Adding 'no-aaaa' restricts queries to IPv4.
echo "[4/7] Optimizing DNS settings to prevent network delays..."
RESOLV_CONF="$PREFIX/etc/resolv.conf"
if [ -f "$RESOLV_CONF" ]; then
    if ! grep -q "no-aaaa" "$RESOLV_CONF" 2>/dev/null; then
        echo "options timeout:1 attempts:2 no-aaaa" >> "$RESOLV_CONF"
        echo "      Applied fast DNS resolver configuration."
    fi
else
    mkdir -p "$(dirname "$RESOLV_CONF")"
    echo "nameserver 8.8.8.8" > "$RESOLV_CONF"
    echo "nameserver 1.1.1.1" >> "$RESOLV_CONF"
    echo "options timeout:1 attempts:2 no-aaaa" >> "$RESOLV_CONF"
    echo "      Created resolv.conf with fast DNS settings."
fi

# ==============================================================================
# [5/7] Antigravity Logo & Title In-Place Patch
# ==============================================================================
# Patches the embedded web bundle inside agy.va39 so the browser tab and
# Android home screen shortcuts display the Antigravity Logo and Title
# instead of the default gift box emoji.
echo "[5/7] Applying Antigravity Logo and Title to Web GUI..."
patch_logo() {
    python3 - << 'PYEOF'
import zipfile, zlib, io, struct, binascii, os, sys, re

prefix = os.environ.get("PREFIX", "/data/data/com.termux/files/usr")
candidates = [
    os.path.join(prefix, "bin", "agy.va39"),
    os.path.join(prefix, "bin", "agy.orig"),
    os.path.join(prefix, "bin", "agy"),
    "bin/agy.va39"
]

target = None
for c in candidates:
    if os.path.isfile(c) and not os.path.islink(c):
        target = c
        break

if not target:
    sys.exit(0)

try:
    with open(target, 'rb') as f:
        data = bytearray(f.read())

    eocd_idx = data.rfind(b'PK\x05\x06')
    if eocd_idx == -1:
        sys.exit(0)

    size_cd = int.from_bytes(data[eocd_idx+12:eocd_idx+16], 'little')
    offset_cd = int.from_bytes(data[eocd_idx+16:eocd_idx+20], 'little')
    zip_start = eocd_idx - size_cd - offset_cd
    zip_end = eocd_idx + 22

    zf = zipfile.ZipFile(io.BytesIO(data[zip_start:zip_end]))
    if 'index.html' not in zf.namelist():
        sys.exit(0)

    info = zf.getinfo('index.html')
    local_hdr_offset = zip_start + info.header_offset
    fn_len = int.from_bytes(data[local_hdr_offset+26:local_hdr_offset+28], 'little')
    extra_len = int.from_bytes(data[local_hdr_offset+28:local_hdr_offset+30], 'little')
    data_offset = local_hdr_offset + 30 + fn_len + extra_len

    old_comp = data[data_offset : data_offset + info.compress_size]
    decomp = zlib.decompress(old_comp, -15)

    gift = b"\xf0\x9f\x8e\x81"
    if gift not in decomp and b'<title>Antigravity CLI</title>' in decomp and b'url(%23m)' in decomp:
        flags = int.from_bytes(data[local_hdr_offset+6:local_hdr_offset+8], 'little')
        if flags & 0x08:
            dd_offset = local_hdr_offset + 30 + fn_len + extra_len + info.compress_size
            if data[dd_offset:dd_offset+4] == b'PK\x07\x08':
                struct.pack_into('<III', data, dd_offset + 4, info.CRC, info.compress_size, info.file_size)
            else:
                struct.pack_into('<III', data, dd_offset, info.CRC, info.compress_size, info.file_size)
            with open(target, 'wb') as f:
                f.write(data)
        sys.exit(0)

    # 1. Update Title
    decomp = decomp.replace(b'<title>Jetski Web</title>', b'<title>Antigravity CLI</title>')

    # 2. Minify comments to ensure compressed size fits within binary limit
    decomp = re.sub(rb'<!--.*?-->\s*', b'', decomp)
    decomp = re.sub(rb'^\s*//.*?\n', b'', decomp, flags=re.MULTILINE)
    decomp = re.sub(rb'\n\s*\n', b'\n', decomp)

    # 3. Replace favicon with official high-fidelity Google Antigravity logo
    old_tag = b"viewBox='0 0 100 100'><text y='.9em' font-size='90'>\xf0\x9f\x8e\x81</text>"
    new_logo = b"viewBox='0 0 24 24'><defs><filter id='b' x='-30%' y='-30%' width='160%' height='160%'><feGaussianBlur stdDeviation='2.8'/></filter><mask id='m'><path d='M21.751 22.607c1.34 1.005 3.35.335 1.508-1.508C17.73 15.74 18.904 1 12.037 1 5.17 1 6.342 15.74.815 21.1c-2.01 2.009.167 2.511 1.507 1.506 5.192-3.517 4.857-9.714 9.715-9.714 4.857 0 4.522 6.197 9.714 9.715z' fill='%23fff'/></mask></defs><g mask='url(%23m)'><rect width='24' height='24' fill='%233186FF'/><g filter='url(%23b)'><ellipse cx='12' cy='2.5' rx='5' ry='3.5' fill='%23FBBC04'/><ellipse cx='13.5' cy='3.5' rx='4' ry='3.5' fill='%23EA4335' opacity='0.8'/><ellipse cx='10' cy='3' rx='3.5' ry='3' fill='%23FFEE48' opacity='0.85'/><ellipse cx='6' cy='8' rx='4.5' ry='4.5' fill='%2300B95C'/><ellipse cx='18' cy='8' rx='4.5' ry='4.5' fill='%23FC413D'/><ellipse cx='12' cy='14' rx='5.5' ry='5.5' fill='%233186FF'/><ellipse cx='4' cy='20' rx='4' ry='4' fill='%233186FF'/><ellipse cx='20' cy='20' rx='4' ry='4' fill='%233186FF'/></g></g>"
    decomp = decomp.replace(old_tag, new_logo)

    # 4. Add apple-touch-icon for Android home-screen shortcuts
    touch_tag = b'''rel="apple-touch-icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><rect width='100' height='100' rx='22' fill='%23202124'/><g transform='translate(14,14) scale(3)'><defs><filter id='bt' x='-30%' y='-30%' width='160%' height='160%'><feGaussianBlur stdDeviation='2.8'/></filter><mask id='mt'><path d='M21.751 22.607c1.34 1.005 3.35.335 1.508-1.508C17.73 15.74 18.904 1 12.037 1 5.17 1 6.342 15.74.815 21.1c-2.01 2.009.167 2.511 1.507 1.506 5.192-3.517 4.857-9.714 9.715-9.714 4.857 0 4.522 6.197 9.714 9.715z' fill='%23fff'/></mask></defs><g mask='url(%23mt)'><rect width='24' height='24' fill='%233186FF'/><g filter='url(%23bt)'><ellipse cx='12' cy='2.5' rx='5' ry='3.5' fill='%23FBBC04'/><ellipse cx='13.5' cy='3.5' rx='4' ry='3.5' fill='%23EA4335' opacity='0.8'/><ellipse cx='10' cy='3' rx='3.5' ry='3' fill='%23FFEE48' opacity='0.85'/><ellipse cx='6' cy='8' rx='4.5' ry='4.5' fill='%2300B95C'/><ellipse cx='18' cy='8' rx='4.5' ry='4.5' fill='%23FC413D'/><ellipse cx='12' cy='14' rx='5.5' ry='5.5' fill='%233186FF'/><ellipse cx='4' cy='20' rx='4' ry='4' fill='%233186FF'/><ellipse cx='20' cy='20' rx='4' ry='4' fill='%233186FF'/></g></g></g></svg>" />\n    <link rel="stylesheet" href="/jetbox.css"'''
    decomp = decomp.replace(b'rel="stylesheet" href="/jetbox.css"', touch_tag)

    new_crc = binascii.crc32(decomp)
    new_uncomp = len(decomp)
    new_comp = zlib.compress(decomp, 9)[2:-4]

    diff = info.compress_size - len(new_comp)
    if diff < 0:
        sys.exit(0)

    pad_bytes = b'XX' + struct.pack('<H', diff - 4) + (b'\x00' * (diff - 4)) if diff >= 4 else (b'\x00' * diff)

    struct.pack_into('<III', data, local_hdr_offset + 14, new_crc, len(new_comp), new_uncomp)
    struct.pack_into('<H', data, local_hdr_offset + 28, diff)

    payload_start = local_hdr_offset + 30 + fn_len
    data[payload_start : payload_start + diff] = pad_bytes
    data[payload_start + diff : payload_start + diff + len(new_comp)] = new_comp

    # Update Streaming Data Descriptor if present (bit 3 of general purpose flag)
    flags = int.from_bytes(data[local_hdr_offset+6:local_hdr_offset+8], 'little')
    if flags & 0x08:
        dd_offset = payload_start + diff + len(new_comp)
        if data[dd_offset:dd_offset+4] == b'PK\x07\x08':
            struct.pack_into('<III', data, dd_offset + 4, new_crc, len(new_comp), new_uncomp)
        else:
            struct.pack_into('<III', data, dd_offset, new_crc, len(new_comp), new_uncomp)

    cd_offset = zip_start + offset_cd
    curr = cd_offset
    while curr < zip_start + offset_cd + size_cd:
        if data[curr:curr+4] != b'PK\x01\x02':
            break
        cd_fn_len = int.from_bytes(data[curr+28:curr+30], 'little')
        cd_extra_len = int.from_bytes(data[curr+30:curr+32], 'little')
        cd_comm_len = int.from_bytes(data[curr+32:curr+34], 'little')
        cd_name = bytes(data[curr+46:curr+46+cd_fn_len]).decode('latin1')
        if cd_name == 'index.html':
            struct.pack_into('<III', data, curr + 16, new_crc, len(new_comp), new_uncomp)
            break
        curr += 46 + cd_fn_len + cd_extra_len + cd_comm_len

    with open(target, 'wb') as f:
        f.write(data)
    print(f"      Applied Antigravity logo to {target}")
except Exception as e:
    pass
PYEOF
}
patch_logo

# ==============================================================================
# [6/7] Google OAuth Token Auto-Sync (Optional Sign-In Bypass)
# ==============================================================================
# If a saved Google OAuth token exists locally, copies it to the CLI config
# directory so the Web GUI opens already logged in. If not found, a one-time
# browser login will occur on first launch.
echo "[6/7] Checking for saved authentication tokens..."
AUTH_DEST="$HOME/.gemini/antigravity-cli"
mkdir -p "$AUTH_DEST"

TOKEN_LOCATIONS=()
if [ -n "$SCRIPT_DIR" ]; then
    TOKEN_LOCATIONS+=("${SCRIPT_DIR}/auth/antigravity-oauth-token")
    TOKEN_LOCATIONS+=("${SCRIPT_DIR}/not project/auth/antigravity-oauth-token")
fi
TOKEN_LOCATIONS+=(
    "/sdcard/Download/antigravity-oauth-token"
    "$HOME/storage/downloads/antigravity-oauth-token"
)

FOUND_TOKEN=0
for token_path in "${TOKEN_LOCATIONS[@]}"; do
    if [ -f "$token_path" ]; then
        cp -p "$token_path" "${AUTH_DEST}/antigravity-oauth-token"
        chmod 600 "${AUTH_DEST}/antigravity-oauth-token"
        echo "      Synchronized Google OAuth token. Sign-in will be bypassed."
        FOUND_TOKEN=1
        break
    fi
done

if [ "$FOUND_TOKEN" -eq 0 ]; then
    echo "      No local token found. First launch will prompt for one-time Google login."
fi

# ==============================================================================
# [7/7] Install Web GUI Launchers (agy-gui & agy-service)
# ==============================================================================
# 1. agy-gui: Foreground launcher featuring auto-patch check, port collision checks,
#    server readiness polling, and multi-opener browser fallbacks.
# 2. agy-service: Background daemon manager supporting start, stop, and logs.
echo "[7/7] Installing GUI launchers and daemon manager..."

# --- agy-gui launcher ---
cat << 'EOF' > "$BIN_DIR/agy-gui"
#!/data/data/com.termux/files/usr/bin/bash
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PORT=4400

for arg in "$@"; do
    case "$arg" in
        --hub-port=*) PORT="${arg#*=}" ;;
    esac
done

URL="http://localhost:${PORT}"

# 1. Ensure fast DNS
RESOLV_CONF="$PREFIX/etc/resolv.conf"
if [ -f "$RESOLV_CONF" ] && ! grep -q "no-aaaa" "$RESOLV_CONF" 2>/dev/null; then
    echo "options timeout:1 attempts:2 no-aaaa" >> "$RESOLV_CONF"
fi

# 2. Check if already running on target port
if curl -s -m 1 "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
    echo "======================================================"
    echo " Antigravity GUI is already running on ${URL}"
    echo " Opening browser..."
    echo "======================================================"
    if command -v termux-open-url >/dev/null 2>&1; then
        termux-open-url "${URL}"
    elif command -v termux-open >/dev/null 2>&1; then
        termux-open "${URL}"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "${URL}"
    fi
    exit 0
fi

# 3. Locate executable engine
AGY_BIN=""
if [ -x "$PREFIX/bin/agy.orig" ]; then
    AGY_BIN="$PREFIX/bin/agy.orig"
elif [ -x "$PREFIX/bin/agy" ]; then
    AGY_BIN="$PREFIX/bin/agy"
fi

if [ -z "$AGY_BIN" ]; then
    echo "[-] Error: Could not locate agy executable in $PREFIX/bin"
    exit 1
fi

# 4. Auto-restore Antigravity logo & title if an upstream update replaced the binary
if command -v python3 >/dev/null 2>&1 && [ -f "$PREFIX/bin/agy.va39" ]; then
    python3 - << 'PYEOF' 2>/dev/null || true
import zipfile, zlib, io, struct, binascii, os, sys, re

target = os.path.expandvars('$PREFIX/bin/agy.va39')
if not os.path.isfile(target):
    sys.exit(0)

try:
    with open(target, 'rb') as f:
        data = bytearray(f.read())

    eocd_idx = data.rfind(b'PK\x05\x06')
    if eocd_idx == -1:
        sys.exit(0)

    size_cd = int.from_bytes(data[eocd_idx+12:eocd_idx+16], 'little')
    offset_cd = int.from_bytes(data[eocd_idx+16:eocd_idx+20], 'little')
    zip_start = eocd_idx - size_cd - offset_cd
    zip_end = eocd_idx + 22

    zf = zipfile.ZipFile(io.BytesIO(data[zip_start:zip_end]))
    if 'index.html' not in zf.namelist():
        sys.exit(0)

    info = zf.getinfo('index.html')
    local_hdr_offset = zip_start + info.header_offset
    fn_len = int.from_bytes(data[local_hdr_offset+26:local_hdr_offset+28], 'little')
    extra_len = int.from_bytes(data[local_hdr_offset+28:local_hdr_offset+30], 'little')
    data_offset = local_hdr_offset + 30 + fn_len + extra_len

    old_comp = data[data_offset : data_offset + info.compress_size]
    decomp = zlib.decompress(old_comp, -15)

    gift = b"\xf0\x9f\x8e\x81"
    if gift not in decomp and b'<title>Antigravity CLI</title>' in decomp and b'url(%23m)' in decomp:
        flags = int.from_bytes(data[local_hdr_offset+6:local_hdr_offset+8], 'little')
        if flags & 0x08:
            dd_offset = local_hdr_offset + 30 + fn_len + extra_len + info.compress_size
            if data[dd_offset:dd_offset+4] == b'PK\x07\x08':
                dd_crc = int.from_bytes(data[dd_offset+4:dd_offset+8], 'little')
                if dd_crc != info.CRC:
                    struct.pack_into('<III', data, dd_offset + 4, info.CRC, info.compress_size, info.file_size)
                    with open(target, 'wb') as f:
                        f.write(data)
        sys.exit(0)

    # 1. Update Title
    decomp = decomp.replace(b'<title>Jetski Web</title>', b'<title>Antigravity CLI</title>')

    # 2. Minify comments to ensure compressed size fits within binary limit
    decomp = re.sub(rb'<!--.*?-->\s*', b'', decomp)
    decomp = re.sub(rb'^\s*//.*?\n', b'', decomp, flags=re.MULTILINE)
    decomp = re.sub(rb'\n\s*\n', b'\n', decomp)

    # 3. Replace favicon with official high-fidelity Google Antigravity logo
    old_tag = b"viewBox='0 0 100 100'><text y='.9em' font-size='90'>\xf0\x9f\x8e\x81</text>"
    new_logo = b"viewBox='0 0 24 24'><defs><filter id='b' x='-30%' y='-30%' width='160%' height='160%'><feGaussianBlur stdDeviation='2.8'/></filter><mask id='m'><path d='M21.751 22.607c1.34 1.005 3.35.335 1.508-1.508C17.73 15.74 18.904 1 12.037 1 5.17 1 6.342 15.74.815 21.1c-2.01 2.009.167 2.511 1.507 1.506 5.192-3.517 4.857-9.714 9.715-9.714 4.857 0 4.522 6.197 9.714 9.715z' fill='%23fff'/></mask></defs><g mask='url(%23m)'><rect width='24' height='24' fill='%233186FF'/><g filter='url(%23b)'><ellipse cx='12' cy='2.5' rx='5' ry='3.5' fill='%23FBBC04'/><ellipse cx='13.5' cy='3.5' rx='4' ry='3.5' fill='%23EA4335' opacity='0.8'/><ellipse cx='10' cy='3' rx='3.5' ry='3' fill='%23FFEE48' opacity='0.85'/><ellipse cx='6' cy='8' rx='4.5' ry='4.5' fill='%2300B95C'/><ellipse cx='18' cy='8' rx='4.5' ry='4.5' fill='%23FC413D'/><ellipse cx='12' cy='14' rx='5.5' ry='5.5' fill='%233186FF'/><ellipse cx='4' cy='20' rx='4' ry='4' fill='%233186FF'/><ellipse cx='20' cy='20' rx='4' ry='4' fill='%233186FF'/></g></g>"
    decomp = decomp.replace(old_tag, new_logo)

    # 4. Add apple-touch-icon
    touch_tag = b'''rel="apple-touch-icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><rect width='100' height='100' rx='22' fill='%23202124'/><g transform='translate(14,14) scale(3)'><defs><filter id='bt' x='-30%' y='-30%' width='160%' height='160%'><feGaussianBlur stdDeviation='2.8'/></filter><mask id='mt'><path d='M21.751 22.607c1.34 1.005 3.35.335 1.508-1.508C17.73 15.74 18.904 1 12.037 1 5.17 1 6.342 15.74.815 21.1c-2.01 2.009.167 2.511 1.507 1.506 5.192-3.517 4.857-9.714 9.715-9.714 4.857 0 4.522 6.197 9.714 9.715z' fill='%23fff'/></mask></defs><g mask='url(%23mt)'><rect width='24' height='24' fill='%233186FF'/><g filter='url(%23bt)'><ellipse cx='12' cy='2.5' rx='5' ry='3.5' fill='%23FBBC04'/><ellipse cx='13.5' cy='3.5' rx='4' ry='3.5' fill='%23EA4335' opacity='0.8'/><ellipse cx='10' cy='3' rx='3.5' ry='3' fill='%23FFEE48' opacity='0.85'/><ellipse cx='6' cy='8' rx='4.5' ry='4.5' fill='%2300B95C'/><ellipse cx='18' cy='8' rx='4.5' ry='4.5' fill='%23FC413D'/><ellipse cx='12' cy='14' rx='5.5' ry='5.5' fill='%233186FF'/><ellipse cx='4' cy='20' rx='4' ry='4' fill='%233186FF'/><ellipse cx='20' cy='20' rx='4' ry='4' fill='%233186FF'/></g></g></g></svg>" />\n    <link rel="stylesheet" href="/jetbox.css"'''
    decomp = decomp.replace(b'rel="stylesheet" href="/jetbox.css"', touch_tag)

    new_crc = binascii.crc32(decomp)
    new_uncomp = len(decomp)
    new_comp = zlib.compress(decomp, 9)[2:-4]

    diff = info.compress_size - len(new_comp)
    if diff >= 0:
        pad_bytes = b'XX' + struct.pack('<H', diff - 4) + (b'\x00' * (diff - 4)) if diff >= 4 else (b'\x00' * diff)
        struct.pack_into('<III', data, local_hdr_offset + 14, new_crc, len(new_comp), new_uncomp)
        struct.pack_into('<H', data, local_hdr_offset + 28, diff)
        payload_start = local_hdr_offset + 30 + fn_len
        data[payload_start : payload_start + diff] = pad_bytes
        data[payload_start + diff : payload_start + diff + len(new_comp)] = new_comp

        flags = int.from_bytes(data[local_hdr_offset+6:local_hdr_offset+8], 'little')
        if flags & 0x08:
            dd_offset = payload_start + diff + len(new_comp)
            if data[dd_offset:dd_offset+4] == b'PK\x07\x08':
                struct.pack_into('<III', data, dd_offset + 4, new_crc, len(new_comp), new_uncomp)
            else:
                struct.pack_into('<III', data, dd_offset, new_crc, len(new_comp), new_uncomp)

        cd_offset = zip_start + offset_cd
        curr = cd_offset
        while curr < zip_start + offset_cd + size_cd:
            if data[curr:curr+4] != b'PK\x01\x02':
                break
            cd_fn_len = int.from_bytes(data[curr+28:curr+30], 'little')
            cd_extra_len = int.from_bytes(data[curr+30:curr+32], 'little')
            cd_comm_len = int.from_bytes(data[curr+32:curr+34], 'little')
            cd_name = bytes(data[curr+46:curr+46+cd_fn_len]).decode('latin1')
            if cd_name == 'index.html':
                struct.pack_into('<III', data, curr + 16, new_crc, len(new_comp), new_uncomp)
                break
            curr += 46 + cd_fn_len + cd_extra_len + cd_comm_len

        with open(target, 'wb') as f:
            f.write(data)
except Exception:
    pass
PYEOF
fi

echo "======================================================"
echo " Starting Antigravity Local Web GUI..."
echo " Engine : ${AGY_BIN}"
echo " URL    : ${URL}"
echo "======================================================"

export AGY_ENABLE_HUB=1

# Auto-open browser as soon as server responds
(
    for i in $(seq 1 30); do
        if curl -s -m 1 "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
            echo "Server ready. Opening ${URL} in browser..."
            if command -v termux-open-url >/dev/null 2>&1; then
                termux-open-url "${URL}"
            elif command -v termux-open >/dev/null 2>&1; then
                termux-open "${URL}"
            elif command -v xdg-open >/dev/null 2>&1; then
                xdg-open "${URL}"
            fi
            break
        fi
        sleep 0.5
    done
) &

exec "$AGY_BIN" --hub "$@"
EOF
chmod +x "$BIN_DIR/agy-gui"
ln -sf "$BIN_DIR/agy-gui" "$BIN_DIR/agy-hub"
ln -sf "$BIN_DIR/agy-gui" "$BIN_DIR/agy-ui"

# --- agy-service daemon manager ---
cat << 'EOF' > "$BIN_DIR/agy-service"
#!/data/data/com.termux/files/usr/bin/bash
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PID_FILE="$HOME/.gemini/antigravity-cli/hub.pid"
LOG_FILE="$HOME/.gemini/antigravity-cli/log/hub.log"
mkdir -p "$HOME/.gemini/antigravity-cli/log"

is_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$PID" ] && ps -p "$PID" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

case "$1" in
    start)
        if is_running; then
            echo "Antigravity Web GUI is already running (PID: $(cat "$PID_FILE"))."
            termux-open-url "http://localhost:4400" >/dev/null 2>&1 || true
            exit 0
        fi
        echo "Starting Antigravity Web GUI in background..."
        AGY_ENABLE_HUB=1 nohup "$PREFIX/bin/agy-gui" > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        sleep 1.5
        echo "Started. URL: http://localhost:4400"
        termux-open-url "http://localhost:4400" >/dev/null 2>&1 || true
        ;;
    stop)
        if is_running; then
            kill $(cat "$PID_FILE") 2>/dev/null || true
            rm -f "$PID_FILE"
            echo "Antigravity Web GUI stopped."
        else
            echo "Antigravity Web GUI is not running."
        fi
        ;;
    logs)
        if [ -f "$LOG_FILE" ]; then
            tail -n 50 -f "$LOG_FILE"
        else
            echo "No log file found at $LOG_FILE"
        fi
        ;;
    *)
        echo "Usage: agy-service {start|stop|logs}"
        ;;
esac
EOF
chmod +x "$BIN_DIR/agy-service"

echo "======================================================"
echo " Installation Complete!"
echo "======================================================"
echo ""
echo " How to use:"
echo "   agy-gui           Launch Web GUI in foreground (opens Chrome)"
echo "   agy-service start Run Web GUI in background"
echo "   agy-service stop  Stop background Web GUI"
echo "   agy-service logs  View background logs"
echo "   agy               Standard CLI (untouched)"
echo ""
echo " Server URL: http://localhost:4400"
echo "======================================================"
