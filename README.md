# Antigravity Local Web GUI for Termux

This repository provides an automated installation and setup guide to run the official Google Antigravity Web GUI inside Termux on Android. It patches the installed Antigravity CLI binary to work directly in your mobile browser as a local Web GUI on port 4400, automatically opening the chat and coding workspace.

---

## Credits & Upstream Projects

This project builds on open source contributions from the community:
- [@wallentx](https://github.com/wallentx): Maintains the automated release builds and packaging in [antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux).
- [@hjotha](https://github.com/hjotha) and [@Brajesh2022](https://github.com/Brajesh2022): Developed the original compatibility fixes and memory patches that allow the Antigravity CLI to run inside Android Termux.

---

## Method 1: Quick Install (Recommended)

Run this command in Termux to install and configure everything automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/dsundaravadhanan-/antigravity-cli-termux-to-gui/main/install.sh | bash
```

Or if running from a local folder:
```bash
bash install.sh
```

### Running from Android Internal Storage

If you copied `install.sh` to your phone's internal storage:
```bash
termux-setup-storage
bash ~/storage/shared/install.sh
```

What the automated installer does:
1. Requests Android storage access via `termux-setup-storage`.
2. Installs `glibc-repo`, `glibc-runner`, and `python`.
3. Downloads the Antigravity CLI binary from upstream.
4. Adds fast DNS settings to prevent network startup delays.
5. Applies the official Antigravity logo and title to the Web GUI.
6. Installs the `agy-gui` launcher and `agy-service` background manager.

---

## Method 2: Two-Step Installation (Upstream CLI + GUI Patch)

If you prefer to separate the core upstream CLI installation from the Web GUI customizer:

### Step 1: Install Upstream Antigravity CLI
Install the core CLI engine directly from [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux):
```bash
export AGY_INSTALL_SKIP_LAUNCH=1
curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash
```

### Step 2: Apply the Web GUI Patch
Run the patch script to configure the web interface, apply the Antigravity logo and title, and create the launchers:
```bash
curl -fsSL "https://raw.githubusercontent.com/dsundaravadhanan-/antigravity-cli-termux-to-gui/main/patch%20agy%20web%20gui.sh" | bash
```

Or if you have the script locally on your phone:
```bash
bash "patch agy web gui.sh"
```

---

## Method 3: Manual Step-by-Step Installation

If you prefer to configure each component manually, run the following steps in sequence:

### 1. Grant Storage Access
```bash
termux-setup-storage
```

### 2. Install Dependencies
Antigravity requires glibc packages and Python for the web logo patch:
```bash
pkg install glibc-repo -y
pkg install glibc-runner -y
pkg install python -y
```

### 3. Install Antigravity CLI
Fetch and install the pre-patched binary from [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux) (skipping interactive terminal launch):
```bash
export AGY_INSTALL_SKIP_LAUNCH=1
curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash
```

### 4. Configure Fast DNS Resolution
Termux can experience connection delays when querying IPv6 records on mobile networks. Restrict lookups to IPv4:
```bash
if [ -f "$PREFIX/etc/resolv.conf" ]; then
    grep -q "no-aaaa" "$PREFIX/etc/resolv.conf" || echo "options timeout:1 attempts:2 no-aaaa" >> "$PREFIX/etc/resolv.conf"
else
    mkdir -p "$PREFIX/etc"
    echo "nameserver 8.8.8.8" > "$PREFIX/etc/resolv.conf"
    echo "nameserver 1.1.1.1" >> "$PREFIX/etc/resolv.conf"
    echo "options timeout:1 attempts:2 no-aaaa" >> "$PREFIX/etc/resolv.conf"
fi
```

### 5. Create the Foreground Launcher (`agy-gui`)
Create `$PREFIX/bin/agy-gui` to start the web server and open Chrome:
```bash
cat << 'EOF' > "$PREFIX/bin/agy-gui"
#!/data/data/com.termux/files/usr/bin/bash
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PORT=4400
URL="http://localhost:${PORT}"

if curl -s -m 1 "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
    echo "Antigravity GUI is already running on ${URL}"
    termux-open-url "${URL}" 2>/dev/null || termux-open "${URL}" 2>/dev/null || xdg-open "${URL}" 2>/dev/null
    exit 0
fi

# Auto-restore Antigravity logo & title if an upstream update replaced the binary
if command -v python3 >/dev/null 2>&1 && [ -f "$PREFIX/bin/agy.va39" ]; then
    python3 - << 'PYEOF' 2>/dev/null || true
import zipfile, zlib, io, struct, binascii, os, sys, re
target = os.path.expandvars('$PREFIX/bin/agy.va39')
if os.path.isfile(target):
    try:
        with open(target, 'rb') as f: data = bytearray(f.read())
        eocd_idx = data.rfind(b'PK\x05\x06')
        if eocd_idx != -1:
            size_cd = int.from_bytes(data[eocd_idx+12:eocd_idx+16], 'little')
            offset_cd = int.from_bytes(data[eocd_idx+16:eocd_idx+20], 'little')
            zip_start = eocd_idx - size_cd - offset_cd
            zf = zipfile.ZipFile(io.BytesIO(data[zip_start:eocd_idx+22]))
            if 'index.html' in zf.namelist():
                info = zf.getinfo('index.html')
                lh = zip_start + info.header_offset
                flen = int.from_bytes(data[lh+26:lh+28], 'little')
                xlen = int.from_bytes(data[lh+28:lh+30], 'little')
                decomp = zlib.decompress(data[lh+30+flen+xlen : lh+30+flen+xlen+info.compress_size], -15)
                if b'\xf0\x9f\x8e\x81' in decomp:
                    decomp = decomp.replace(b'<title>Jetski Web</title>', b'<title>Antigravity CLI</title>')
                    decomp = re.sub(rb'<!--.*?-->\s*', b'', decomp)
                    decomp = re.sub(rb'^\s*//.*?\n', b'', decomp, flags=re.MULTILINE)
                    decomp = re.sub(rb'\n\s*\n', b'\n', decomp)
                    old_icon = b"viewBox='0 0 100 100'><text y='.9em' font-size='90'>\xf0\x9f\x8e\x81</text>"
                    new_icon = b"viewBox='0 0 24 24'><defs><filter id='b' x='-30%' y='-30%' width='160%' height='160%'><feGaussianBlur stdDeviation='2.8'/></filter><mask id='m'><path d='M21.751 22.607c1.34 1.005 3.35.335 1.508-1.508C17.73 15.74 18.904 1 12.037 1 5.17 1 6.342 15.74.815 21.1c-2.01 2.009.167 2.511 1.507 1.506 5.192-3.517 4.857-9.714 9.715-9.714 4.857 0 4.522 6.197 9.714 9.715z' fill='%23fff'/></mask></defs><g mask='url(%23m)'><rect width='24' height='24' fill='%233186FF'/><g filter='url(%23b)'><ellipse cx='12' cy='2.5' rx='5' ry='3.5' fill='%23FBBC04'/><ellipse cx='13.5' cy='3.5' rx='4' ry='3.5' fill='%23EA4335' opacity='0.8'/><ellipse cx='10' cy='3' rx='3.5' ry='3' fill='%23FFEE48' opacity='0.85'/><ellipse cx='6' cy='8' rx='4.5' ry='4.5' fill='%2300B95C'/><ellipse cx='18' cy='8' rx='4.5' ry='4.5' fill='%23FC413D'/><ellipse cx='12' cy='14' rx='5.5' ry='5.5' fill='%233186FF'/><ellipse cx='4' cy='20' rx='4' ry='4' fill='%233186FF'/><ellipse cx='20' cy='20' rx='4' ry='4' fill='%233186FF'/></g></g>"
                    decomp = decomp.replace(old_icon, new_icon)
                    touch_tag = b'''rel="apple-touch-icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><rect width='100' height='100' rx='22' fill='%23202124'/><g transform='translate(14,14) scale(3)'><defs><filter id='bt' x='-30%' y='-30%' width='160%' height='160%'><feGaussianBlur stdDeviation='2.8'/></filter><mask id='mt'><path d='M21.751 22.607c1.34 1.005 3.35.335 1.508-1.508C17.73 15.74 18.904 1 12.037 1 5.17 1 6.342 15.74.815 21.1c-2.01 2.009.167 2.511 1.507 1.506 5.192-3.517 4.857-9.714 9.715-9.714 4.857 0 4.522 6.197 9.714 9.715z' fill='%23fff'/></mask></defs><g mask='url(%23mt)'><rect width='24' height='24' fill='%233186FF'/><g filter='url(%23bt)'><ellipse cx='12' cy='2.5' rx='5' ry='3.5' fill='%23FBBC04'/><ellipse cx='13.5' cy='3.5' rx='4' ry='3.5' fill='%23EA4335' opacity='0.8'/><ellipse cx='10' cy='3' rx='3.5' ry='3' fill='%23FFEE48' opacity='0.85'/><ellipse cx='6' cy='8' rx='4.5' ry='4.5' fill='%2300B95C'/><ellipse cx='18' cy='8' rx='4.5' ry='4.5' fill='%23FC413D'/><ellipse cx='12' cy='14' rx='5.5' ry='5.5' fill='%233186FF'/><ellipse cx='4' cy='20' rx='4' ry='4' fill='%233186FF'/><ellipse cx='20' cy='20' rx='4' ry='4' fill='%233186FF'/></g></g></g></svg>" />\n    <link rel="stylesheet" href="/jetbox.css"'''
                    decomp = decomp.replace(b'rel="stylesheet" href="/jetbox.css"', touch_tag)
                    ncrc = binascii.crc32(decomp)
                    ncomp = zlib.compress(decomp, 9)[2:-4]
                    diff = info.compress_size - len(ncomp)
                    if diff >= 0:
                        pad = b'XX' + struct.pack('<H', diff - 4) + (b'\x00' * (diff - 4)) if diff >= 4 else (b'\x00' * diff)
                        struct.pack_into('<III', data, lh + 14, ncrc, len(ncomp), len(decomp))
                        struct.pack_into('<H', data, lh + 28, diff)
                        pstart = lh + 30 + flen
                        data[pstart : pstart + diff] = pad
                        data[pstart + diff : pstart + diff + len(ncomp)] = ncomp
                        if int.from_bytes(data[lh+6:lh+8], 'little') & 0x08:
                            dd = pstart + diff + len(ncomp)
                            struct.pack_into('<III', data, dd + 4 if data[dd:dd+4] == b'PK\x07\x08' else dd, ncrc, len(ncomp), len(decomp))
                        curr = zip_start + offset_cd
                        while curr < zip_start + offset_cd + size_cd:
                            if data[curr:curr+4] != b'PK\x01\x02': break
                            cflen = int.from_bytes(data[curr+28:curr+30], 'little')
                            if bytes(data[curr+46:curr+46+cflen]).decode('latin1') == 'index.html':
                                struct.pack_into('<III', data, curr + 16, ncrc, len(ncomp), len(decomp))
                                break
                            curr += 46 + cflen + int.from_bytes(data[curr+30:curr+32], 'little') + int.from_bytes(data[curr+32:curr+34], 'little')
                        with open(target, 'wb') as f: f.write(data)
    except Exception: pass
PYEOF
fi

export AGY_ENABLE_HUB=1

(
    for i in $(seq 1 30); do
        if curl -s -m 1 "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
            termux-open-url "${URL}" 2>/dev/null || termux-open "${URL}" 2>/dev/null || xdg-open "${URL}" 2>/dev/null
            break
        fi
        sleep 0.5
    done
) &

exec "$PREFIX/bin/agy" --hub "$@"
EOF
chmod +x "$PREFIX/bin/agy-gui"
ln -sf "$PREFIX/bin/agy-gui" "$PREFIX/bin/agy-hub"
```

### 6. Create the Background Daemon Manager (`agy-service`)
Create `$PREFIX/bin/agy-service` to run the GUI as a background process:
```bash
cat << 'EOF' > "$PREFIX/bin/agy-service"
#!/data/data/com.termux/files/usr/bin/bash
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
PID_FILE="$HOME/.gemini/antigravity-cli/hub.pid"
LOG_FILE="$HOME/.gemini/antigravity-cli/log/hub.log"
mkdir -p "$HOME/.gemini/antigravity-cli/log"

is_running() {
    [ -f "$PID_FILE" ] && ps -p "$(cat "$PID_FILE" 2>/dev/null)" >/dev/null 2>&1
}

case "$1" in
    start)
        if is_running; then
            echo "Antigravity Web GUI is already running (PID: $(cat "$PID_FILE"))."
            termux-open-url "http://localhost:4400" >/dev/null 2>&1 || true
            exit 0
        fi
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
        [ -f "$LOG_FILE" ] && tail -n 50 -f "$LOG_FILE" || echo "No logs found."
        ;;
    *)
        echo "Usage: agy-service {start|stop|logs}"
        ;;
esac
EOF
chmod +x "$PREFIX/bin/agy-service"
```

---

## Daily Usage

### Option A: Foreground Mode
Runs directly in your active Termux window. Press `Ctrl+C` to stop.
```bash
agy-gui
```

### Option B: Background Service Mode
Runs in the background, allowing you to minimize or close Termux while keeping the web workspace active in Chrome:
```bash
agy-service start   # Starts the server in background and opens Chrome
agy-service stop    # Stops the background server
agy-service logs    # Views recent output for troubleshooting
```

### Option C: Text CLI Mode
Use standard command-line mode without starting the web server:
```bash
agy
```

---

## How It Works

1. **Embedded Assets**: The Antigravity engine binary contains Google's React frontend bundle embedded internally. When launched with `--hub`, it serves these static assets over local HTTP on port 4400.
2. **Browser Launch**: The launcher polls `http://127.0.0.1:4400` until the server responds, then invokes `termux-open-url` to launch your Android browser.
3. **Authentication**: After completing Google Sign-In in your browser on initial launch, the OAuth token is stored at `~/.gemini/antigravity-cli/antigravity-oauth-token`. Subsequent launches remain logged in automatically.
