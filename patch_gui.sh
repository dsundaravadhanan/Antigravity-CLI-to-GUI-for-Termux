#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# Antigravity Web GUI Post-Installation Customizer & Auto-Update Engine
# ==============================================================================
# Configures the local Web GUI, applies the Antigravity logo & title patch,
# optimizes network DNS resolution, generates launcher utilities, and includes
# an intelligent dynamic CRC repair engine and post-update hook so any
# past or future agy update always leaves the Web GUI 100% operational.
# ==============================================================================
set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
BIN_DIR="${PREFIX}/bin"

# Parse CLI arguments
SILENT=0
POST_UPDATE=0
for arg in "$@"; do
    case "$arg" in
        --silent|-s|-q|--quiet) SILENT=1 ;;
        --post-update) POST_UPDATE=1; SILENT=1 ;;
    esac
done

# Determine script directory safely
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR=""
fi

if [ "$SILENT" -eq 0 ]; then
    echo "======================================================"
    echo "    Antigravity Web GUI Post-Installation Patch       "
    echo "======================================================"
fi

# ==============================================================================
# [1/6] Pre-flight Verification
# ==============================================================================
if [ "$SILENT" -eq 0 ]; then
    echo "[1/6] Verifying existing Antigravity installation..."
fi

if [ ! -f "$BIN_DIR/agy" ] && [ ! -f "$BIN_DIR/agy.real" ] && [ ! -f "$BIN_DIR/agy.va39" ]; then
    echo "[-] Error: Antigravity CLI binaries not found in $BIN_DIR."
    echo "    Please install Antigravity CLI first with:"
    echo "    curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash"
    exit 1
fi

# Ensure Python 3 is installed for binary patching
if ! command -v python3 >/dev/null 2>&1; then
    if [ "$SILENT" -eq 0 ]; then
        echo "      Installing Python runtime for web asset patch..."
    fi
    pkg install python -y
fi

if [ "$SILENT" -eq 0 ]; then
    echo "      Found Antigravity installation and Python runtime."
fi

# ==============================================================================
# [2/6] Network & Fast DNS Configuration (Fix IPv6 Latency)
# ==============================================================================
if [ "$SILENT" -eq 0 ]; then
    echo "[2/6] Optimizing DNS settings to prevent network delays..."
fi
RESOLV_CONF="$PREFIX/etc/resolv.conf"
if [ -f "$RESOLV_CONF" ]; then
    if ! grep -q "no-aaaa" "$RESOLV_CONF" 2>/dev/null; then
        echo "options timeout:1 attempts:2 no-aaaa" >> "$RESOLV_CONF"
        [ "$SILENT" -eq 0 ] && echo "      Applied fast DNS resolver configuration."
    else
        [ "$SILENT" -eq 0 ] && echo "      DNS resolver already optimized."
    fi
else
    mkdir -p "$(dirname "$RESOLV_CONF")"
    echo "nameserver 8.8.8.8" > "$RESOLV_CONF"
    echo "nameserver 1.1.1.1" >> "$RESOLV_CONF"
    echo "options timeout:1 attempts:2 no-aaaa" >> "$RESOLV_CONF"
    [ "$SILENT" -eq 0 ] && echo "      Created resolv.conf with fast DNS settings."
fi

# ==============================================================================
# [3/6] Universal Dynamic Asset Repair & In-Place Logo/Title Patch
# ==============================================================================
if [ "$SILENT" -eq 0 ]; then
    echo "[3/6] Validating web assets and applying Antigravity branding..."
fi

patch_and_repair_assets() {
    python3 - << 'PYEOF'
import zipfile, zlib, io, struct, binascii, os, sys, re

prefix = os.environ.get("PREFIX", "/data/data/com.termux/files/usr")
candidates = [
    os.path.join(prefix, "bin", "agy.va39"),
    os.path.join(prefix, "bin", "agy.orig"),
    os.path.join(prefix, "bin", "agy.real"),
    os.path.join(prefix, "bin", "agy"),
    "bin/agy.va39"
]

target = None
for c in candidates:
    if os.path.isfile(c) and not os.path.islink(c):
        try:
            with open(c, 'rb') as tf:
                if tf.read(4) == b'\x7fELF':
                    target = c
                    break
        except Exception:
            pass

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

    # --- Phase A: Dynamic Universal Asset Repair ---
    zf = zipfile.ZipFile(io.BytesIO(data[zip_start:zip_end]))
    bad_file = zf.testzip()

    if bad_file:
        print(f"      Detected upstream asset corruption in '{bad_file}'. Repairing...")
        b_info = zf.getinfo(bad_file)
        b_lh = zip_start + b_info.header_offset
        b_fn_len = int.from_bytes(data[b_lh+26:b_lh+28], 'little')
        b_extra_len = int.from_bytes(data[b_lh+28:b_lh+30], 'little')
        b_comp_start = b_lh + 30 + b_fn_len + b_extra_len
        b_comp_end = b_comp_start + b_info.compress_size
        target_crc = b_info.CRC
        target_usize = b_info.file_size

        start_aligned = (b_comp_start // 4) * 4
        end_aligned = ((b_comp_end + 3) // 4) * 4

        def get_w(off): return struct.unpack_from('<I', data, off)[0]

        candidates = []
        for off in range(start_aligned, end_aligned, 4):
            w = get_w(off)
            if (w & 0x7F800000) == 0x53000000:
                immr = (w >> 16) & 0x3F
                imms = (w >> 10) & 0x3F
                if immr == 35 and imms == 37:
                    orig_w = (w & ~((0x3F << 16) | (0x3F << 10))) | (42 << 16) | (44 << 10)
                    candidates.append((off, w, orig_w))
                elif immr == 29 and imms == 28:
                    orig_w = (w & ~((0x3F << 16) | (0x3F << 10))) | (22 << 16) | (21 << 10)
                    candidates.append((off, w, orig_w))

        if candidates and len(candidates) <= 20:
            n = len(candidates)
            solved = False
            for mask in range(1, 1 << n):
                for i in range(n):
                    struct.pack_into('<I', data, candidates[i][0], candidates[i][2] if ((mask >> i) & 1) else candidates[i][1])

                comp_slice = data[b_comp_start : b_comp_end]
                try:
                    decomp = zlib.decompress(comp_slice, -15)
                    if len(decomp) == target_usize and binascii.crc32(decomp) == target_crc:
                        solved = True
                        break
                except Exception:
                    pass

            if solved:
                with open(target, 'wb') as f:
                    f.write(data)
                print(f"      Successfully repaired '{bad_file}'! Zero CRC errors remain.")

        # Re-verify ZIP after repair
        zf = zipfile.ZipFile(io.BytesIO(data[zip_start:zip_end]))

    # --- Phase B: In-Place Safe Logo & Title Patch (Isolated) ---
    try:
        if 'index.html' not in zf.namelist():
            sys.exit(0)

        info = zf.getinfo('index.html')
        local_hdr_offset = zip_start + info.header_offset
        fn_len = int.from_bytes(data[local_hdr_offset+26:local_hdr_offset+28], 'little')
        old_extra_len = int.from_bytes(data[local_hdr_offset+28:local_hdr_offset+30], 'little')
        data_offset = local_hdr_offset + 30 + fn_len + old_extra_len

        old_comp = data[data_offset : data_offset + info.compress_size]
        decomp = zlib.decompress(old_comp, -15)

        gift = b"\xf0\x9f\x8e\x81"
        if gift not in decomp and b'<title>Antigravity CLI</title>' in decomp and b'url(%23m)' in decomp:
            with open(target, 'wb') as f:
                f.write(data)
            print(f"      Antigravity branding verified on {target}")
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
        if diff < 0:
            print("      Notice: Compressed payload exceeded space limits. Skipping branding patch.")
        else:
            old_extra = data[local_hdr_offset + 30 + fn_len : local_hdr_offset + 30 + fn_len + old_extra_len]
            pad_bytes = b'XX' + struct.pack('<H', diff - 4) + (b'\x00' * (diff - 4)) if diff >= 4 else (b'\x00' * diff)
            new_extra = old_extra + pad_bytes
            new_extra_len = len(new_extra)

            struct.pack_into('<III', data, local_hdr_offset + 14, new_crc, len(new_comp), new_uncomp)
            struct.pack_into('<H', data, local_hdr_offset + 28, new_extra_len)

            payload_start = local_hdr_offset + 30 + fn_len
            data[payload_start : payload_start + new_extra_len] = new_extra
            data[payload_start + new_extra_len : payload_start + new_extra_len + len(new_comp)] = new_comp

            flags = int.from_bytes(data[local_hdr_offset+6:local_hdr_offset+8], 'little')
            if flags & 0x08:
                dd_offset = payload_start + new_extra_len + len(new_comp)
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
            print(f"      Applied Antigravity branding to {target}")
    except Exception as e:
        print(f"      Notice: Branding patch skipped ({e}). Running with default branding.")
except Exception as e:
    print(f"      Warning: Asset processing failed: {e}")
PYEOF
}
patch_and_repair_assets

# ==============================================================================
# [4/6] Google OAuth Token Auto-Sync (Optional Sign-In Bypass)
# ==============================================================================
if [ "$SILENT" -eq 0 ]; then
    echo "[4/6] Checking for saved authentication tokens..."
fi
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
    "$HOME/storage/shared/Download/antigravity-oauth-token"
)

COPIED=0
for src in "${TOKEN_LOCATIONS[@]}"; do
    if [ -f "$src" ]; then
        cp -p "$src" "$AUTH_DEST/antigravity-oauth-token"
        chmod 600 "$AUTH_DEST/antigravity-oauth-token"
        [ "$SILENT" -eq 0 ] && echo "      Imported authentication token from: $src"
        COPIED=1
        break
    fi
done

if [ "$COPIED" -eq 0 ] && [ "$SILENT" -eq 0 ]; then
    if [ -f "$AUTH_DEST/antigravity-oauth-token" ]; then
        echo "      Existing authentication token found."
    else
        echo "      No local token detected. You can log in via browser on first launch."
    fi
fi

# ==============================================================================
# [5/6] Install Automatic Post-Update Hook & CLI Wrapper
# ==============================================================================
if [ "$SILENT" -eq 0 ]; then
    echo "[5/6] Installing automatic update hook and wrapper..."
fi

# 1. Install patch_gui.sh as agy-patch utility in PATH
cp -f "$0" "$BIN_DIR/agy-patch" 2>/dev/null || true
chmod +x "$BIN_DIR/agy-patch" 2>/dev/null || true

# 2. Preserve native binary as agy.real if not already separated
if [ -f "$BIN_DIR/agy" ]; then
    if ! head -n 1 "$BIN_DIR/agy" 2>/dev/null | grep -q "bash"; then
        mv -f "$BIN_DIR/agy" "$BIN_DIR/agy.real"
    fi
fi

# 3. Create persistent agy wrapper with auto-update hook
cat << 'EOF' > "$BIN_DIR/agy"
#!/data/data/com.termux/files/usr/bin/bash
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BIN_DIR="${PREFIX}/bin"

REAL_BIN="$BIN_DIR/agy.real"
if [ ! -x "$REAL_BIN" ]; then
    if [ -x "$BIN_DIR/agy.orig" ]; then
        REAL_BIN="$BIN_DIR/agy.orig"
    elif [ -x "$BIN_DIR/agy.va39" ]; then
        REAL_BIN="$BIN_DIR/agy.va39"
    else
        echo "[-] Error: Native Antigravity CLI binary not found in $BIN_DIR"
        exit 1
    fi
fi

if [ "${1:-}" = "update" ]; then
    echo "[agy-gui] Running Antigravity upstream updater..."
    "$REAL_BIN" "$@"
    UPDATE_STATUS=$?

    if [ $UPDATE_STATUS -eq 0 ]; then
        echo "[agy-gui] Update complete. Applying Web GUI patch to updated binary..."
        if [ -f "$BIN_DIR/agy" ] && ! head -n 1 "$BIN_DIR/agy" 2>/dev/null | grep -q "bash"; then
            mv -f "$BIN_DIR/agy" "$BIN_DIR/agy.real"
            [ -x "$BIN_DIR/agy-patch" ] && "$BIN_DIR/agy-patch" --post-update || true
        else
            [ -x "$BIN_DIR/agy-patch" ] && "$BIN_DIR/agy-patch" --post-update || true
        fi
        echo "[agy-gui] Web GUI is ready and up to date."
    fi
    exit $UPDATE_STATUS
fi

exec "$REAL_BIN" "$@"
EOF
chmod +x "$BIN_DIR/agy"

# ==============================================================================
# [6/6] Create Launcher Scripts (agy-gui and agy-service)
# ==============================================================================
if [ "$SILENT" -eq 0 ]; then
    echo "[6/6] Generating launcher scripts..."
fi

# --- agy-gui foreground launcher ---
cat << 'EOF' > "$BIN_DIR/agy-gui"
#!/data/data/com.termux/files/usr/bin/bash
# Foreground launcher for Antigravity Local Web GUI
set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PORT=4400

# Parse custom port if provided
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
if [ -x "$PREFIX/bin/agy.real" ]; then
    AGY_BIN="$PREFIX/bin/agy.real"
elif [ -x "$PREFIX/bin/agy.orig" ]; then
    AGY_BIN="$PREFIX/bin/agy.orig"
elif [ -x "$PREFIX/bin/agy" ]; then
    AGY_BIN="$PREFIX/bin/agy"
fi

if [ -z "$AGY_BIN" ]; then
    echo "[-] Error: Could not locate agy executable in $PREFIX/bin"
    exit 1
fi

# 4. Auto-verify and restore GUI patch if upstream replaced binary
if [ -x "$PREFIX/bin/agy-patch" ]; then
    "$PREFIX/bin/agy-patch" --silent >/dev/null 2>&1 || true
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
    status)
        if is_running; then
            echo "Antigravity Web GUI is active (PID: $(cat "$PID_FILE"), Port: 4400)"
        else
            echo "Antigravity Web GUI is stopped."
        fi
        ;;
    restart)
        "$0" stop
        sleep 1
        "$0" start
        ;;
    logs)
        if [ -f "$LOG_FILE" ]; then
            tail -n 50 -f "$LOG_FILE"
        else
            echo "No log file found at: $LOG_FILE"
        fi
        ;;
    *)
        echo "Usage: agy-service {start|stop|status|restart|logs}"
        exit 1
        ;;
esac
EOF
chmod +x "$BIN_DIR/agy-service"

if [ "$SILENT" -eq 0 ]; then
    echo "======================================================"
    echo "    Post-Installation Patch Applied Successfully      "
    echo "======================================================"
    echo ""
    echo "Automatic update protection is active:"
    echo "  Running 'agy update' will now auto-patch the GUI!"
    echo ""
    echo "Launch commands:"
    echo "  agy-gui           (runs in foreground with live terminal output)"
    echo "  agy-service start (runs as background process)"
    echo ""
fi
