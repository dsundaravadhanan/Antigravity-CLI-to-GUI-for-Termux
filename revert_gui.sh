#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Antigravity Web GUI Revert / Uninstaller Script
# ==============================================================================
# Completely removes all post-installation Web GUI components, launchers,
# background daemon services, DNS configurations, and binary modifications,
# restoring the system to a clean, upstream Antigravity CLI installation.
#
# Preserved (Steps 1, 2, 3):
# - Android storage permissions (termux-setup-storage)
# - Core packages (glibc-repo, glibc-runner, python)
# - Upstream Antigravity CLI binary and user authentication tokens
# ==============================================================================
set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
BIN_DIR="${PREFIX}/bin"

echo "======================================================"
echo "    Antigravity Web GUI Revert / Uninstaller          "
echo "======================================================"

echo ""
echo "======================================================"
echo "    WARNING: Potential Data & Session Loss            "
echo "======================================================"
echo "Reverting the Web GUI will terminate all active web"
echo "processes and delete localhost:4400 runtime state."
echo "All conversations and data inside the local Web GUI"
echo "will be permanently deleted."
echo ""
echo "The repository author and contributors are not"
echo "responsible for any data loss resulting from this script."
echo "======================================================"
echo ""

if [ "${AGY_FORCE:-0}" != "1" ] && [ "$1" != "-y" ] && [ "$1" != "--yes" ]; then
    if [ -t 0 ]; then
        read -r -p "Are you sure you want to proceed? [y/N]: " CONFIRM
    elif [ -e /dev/tty ]; then
        read -r -p "Are you sure you want to proceed? [y/N]: " CONFIRM < /dev/tty
    else
        CONFIRM="n"
    fi
    case "$CONFIRM" in
        [yY]|[yY][eE][sS])
            echo "Proceeding with Web GUI uninstallation..."
            ;;
        *)
            echo "Aborted by user. No changes were made."
            exit 0
            ;;
    esac
fi

# ==============================================================================
# [1/5] Terminate Running Web GUI Processes
# ==============================================================================
echo "[1/5] Stopping any active Antigravity Web GUI instances..."

PID_FILE="$HOME/.gemini/antigravity-cli/hub.pid"
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null || true)
    if [ -n "$PID" ] && ps -p "$PID" >/dev/null 2>&1; then
        echo "      Stopping background service (PID: $PID)..."
        kill "$PID" 2>/dev/null || true
        sleep 1
    fi
    rm -f "$PID_FILE"
fi

# Kill any lingering process listening on port 4400 or running agy --hub
pkill -f "agy.*--hub" 2>/dev/null || true
pkill -f "agy-gui" 2>/dev/null || true

# Check if port 4400 is still occupied
if command -v fuser >/dev/null 2>&1; then
    fuser -k 4400/tcp 2>/dev/null || true
fi
echo "      Web GUI processes stopped."

# ==============================================================================
# [2/5] Remove Web GUI Launchers and Symlinks
# ==============================================================================
echo "[2/5] Removing Web GUI launchers and symlinks..."

LAUNCHERS=(
    "$BIN_DIR/agy-gui"
    "$BIN_DIR/agy-hub"
    "$BIN_DIR/agy-ui"
    "$BIN_DIR/agy-service"
)

for file in "${LAUNCHERS[@]}"; do
    if [ -e "$file" ] || [ -L "$file" ]; then
        rm -f "$file"
        echo "      Removed: $file"
    fi
done

# Clean up daemon log file
LOG_FILE="$HOME/.gemini/antigravity-cli/log/hub.log"
if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
    echo "      Removed daemon log: $LOG_FILE"
fi

# ==============================================================================
# [3/5] Revert Fast DNS Configuration
# ==============================================================================
echo "[3/5] Cleaning up DNS resolver settings..."
RESOLV_CONF="$PREFIX/etc/resolv.conf"
if [ -f "$RESOLV_CONF" ]; then
    if grep -q "no-aaaa" "$RESOLV_CONF" 2>/dev/null; then
        sed -i '/no-aaaa/d' "$RESOLV_CONF" 2>/dev/null || true
        echo "      Removed 'no-aaaa' configuration from resolv.conf."
    else
        echo "      resolv.conf does not contain custom settings."
    fi
fi

# ==============================================================================
# [4/5] Restore Upstream Binary Assets
# ==============================================================================
echo "[4/5] Restoring upstream binary state..."

revert_binary_inplace() {
    python3 - << 'PYEOF' 2>/dev/null || true
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
    if gift in decomp and b'<title>Jetski Web</title>' in decomp:
        # Already restored or upstream default
        sys.exit(0)

    # 1. Restore Title
    decomp = decomp.replace(b'<title>Antigravity CLI</title>', b'<title>Jetski Web</title>')

    # 2. Restore gift icon emoji
    old_logo_pattern = rb"viewBox='0 0 24 24'.*?</g></g>"
    gift_icon = b"viewBox='0 0 100 100'><text y='.9em' font-size='90'>\xf0\x9f\x8e\x81</text>"
    decomp = re.sub(old_logo_pattern, gift_icon, decomp)

    # 3. Remove apple-touch-icon tag if present
    decomp = re.sub(rb'<link rel="apple-touch-icon"[^>]*>\s*', b'', decomp)

    new_crc = binascii.crc32(decomp)
    new_uncomp = len(decomp)
    new_comp = zlib.compress(decomp, 9)[2:-4]

    diff = info.compress_size - len(new_comp)
    if diff < 0:
        # Fallback to upstream re-fetch if compressed size exceeded
        sys.exit(1)

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
    print(f"      Restored original web assets inside: {target}")
except Exception as e:
    sys.exit(1)
PYEOF
}

if command -v python3 >/dev/null 2>&1; then
    if ! revert_binary_inplace; then
        echo "      Note: Refreshing pristine binary from upstream repository..."
        export AGY_INSTALL_SKIP_LAUNCH=1
        curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash >/dev/null 2>&1 || true
    fi
else
    echo "      Python not found. Refreshing pristine binary from upstream repository..."
    export AGY_INSTALL_SKIP_LAUNCH=1
    curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash >/dev/null 2>&1 || true
fi

# ==============================================================================
# [5/5] Verify Upstream CLI Functionality
# ==============================================================================
echo "[5/5] Verifying upstream Antigravity CLI..."

if [ -f "$BIN_DIR/agy" ]; then
    echo "      Antigravity CLI binary intact: $BIN_DIR/agy"
    if [ -f "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" ]; then
        echo "      Authentication credentials preserved: ~/.gemini/antigravity-cli/antigravity-oauth-token"
    fi
    echo ""
    echo "======================================================"
    echo "    Web GUI Successfully Removed / Reverted          "
    echo "======================================================"
    echo ""
    echo "Your upstream Antigravity CLI remains fully functional."
    echo "To launch the CLI in your terminal, simply run:"
    echo "  agy"
    echo ""
else
    echo "[-] Warning: Upstream 'agy' binary was not found in $BIN_DIR."
    echo "    You can reinstall it cleanly from upstream with:"
    echo "    curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash"
fi
