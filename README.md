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
curl -fsSL https://raw.githubusercontent.com/dsundaravadhanan/antigravity-cli-termux-to-gui/main/install.sh | bash
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

### Step 1: Install Upstream Antigravity CLI (Skip if already installed)
Install the core CLI engine directly from [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux):
```bash
export AGY_INSTALL_SKIP_LAUNCH=1
curl -fsSL https://raw.githubusercontent.com/wallentx/antigravity-cli-termux/dev/install.sh | bash
```

### Step 2: Apply the Web GUI Patch
Run the patch script to configure the web interface, apply the Antigravity logo and title, and create the launchers:
```bash
curl -fsSL https://raw.githubusercontent.com/dsundaravadhanan/antigravity-cli-termux-to-gui/main/patch_gui.sh | bash
```

Or if you have the script locally on your phone:
```bash
bash patch_gui.sh
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
    echo "Antigravity GUI is already running on ${URL}"
    termux-open-url "${URL}" 2>/dev/null || termux-open "${URL}" 2>/dev/null || xdg-open "${URL}" 2>/dev/null
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

exec "$AGY_BIN" --hub "$@"
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

## Standalone Android App Experience

The Web GUI can be installed to your Android home screen via Chrome to provide a dedicated standalone app experience:

1. Start the server using `agy-gui` or `agy-service start`.
2. When the Web GUI opens in Chrome at `http://localhost:4400`, tap the **three dots menu (⋮)** in the top-right corner.
3. Select **Install app** (or **Add to Home screen**).
4. Tap **Install**.

The patched official Google Antigravity icon will be added to your Android home screen. Tapping it opens Antigravity in full-screen standalone app mode without browser toolbars or address bars.

---

## Authentication

The CLI authenticates with Google Account credentials:

- **Web GUI Sign-In**:
  1. On first launch, sign-in is prompted directly inside the Web GUI (`http://localhost:4400`).
  2. Tap **Sign In** to redirect to a new browser tab and complete Google authentication.
  3. Once signed in, return to the `localhost:4400` tab and wait a few moments; the Antigravity workspace will open automatically.
- **Session Storage**: OAuth credentials are saved locally at `~/.gemini/antigravity-cli/antigravity-oauth-token` so subsequent launches remain signed in.
- **Sign Out**: Sign-out should be performed directly within the Web GUI interface via your account settings to clear active session credentials.
- **Session Isolation (Web GUI vs. Termux CLI)**: The Web GUI running on `localhost:4400` is completely separated from the Termux terminal CLI. All conversations and data inside the browser Web GUI are not visible, mirrored, or shared with the Termux terminal prompt, and vice versa.

---

## Terms of Service & Data Use

> [!WARNING]
> Autonomous AI coding agents carry inherent security risks, including autonomous command execution, prompt injection, and environment changes. Always monitor and verify actions taken by the agent.

By using Antigravity CLI, you agree to Google's product terms and data use policies:
- **Terms of Service**: [antigravity.google/terms](https://antigravity.google/terms)
- **Privacy Policy**: [policies.google.com/privacy](https://policies.google.com/privacy)

---

## How It Works

1. **100% Standalone on Android (No PC Required)**: Only your Android phone and an internet connection are needed. Unlike remote desktop streamers or relay proxies, the complete Antigravity CLI engine runs natively on your phone inside Termux, delivering the official Google Antigravity desktop Web GUI experience directly in your mobile browser.
2. **Embedded Web Assets**: The compiled engine binary contains Google's official React web bundle internally. When executed with `--hub`, it serves this full desktop interface locally over HTTP on port 4400.
3. **Automated Browser Launch**: The launcher polls `http://127.0.0.1:4400` until the local server is ready, then automatically opens your default Android browser directly into the workspace.
4. **Token Management**: Google OAuth tokens stored at `~/.gemini/antigravity-cli/antigravity-oauth-token` are automatically loaded on each launch for immediate authentication.

---

## Reverting / Uninstalling Web GUI

> [!WARNING]
> **Data Loss & Session Disclaimer**: Running `revert_gui.sh` forcibly terminates active web server processes and cleans local runtime state. All conversations and data inside `localhost:4400` will be permanently deleted. Back up any critical code, prompts, or chat outputs prior to running this script. The repository author and contributors accept no responsibility or legal liability for any data loss, lost conversations, or workflow disruptions caused by executing this uninstaller (see [DISCLAIMER.md](DISCLAIMER.md)).

To remove all Web GUI customizations, background daemon services, launchers, and binary patches, run:

```bash
curl -fsSL https://raw.githubusercontent.com/dsundaravadhanan/antigravity-cli-termux-to-gui/main/revert_gui.sh | bash
```

Or run locally:
```bash
bash revert_gui.sh
```

What `revert_gui.sh` does:
1. **Stops Web GUI Processes**: Terminates active port 4400 and background daemon processes.
2. **Removes Launchers**: Deletes `$PREFIX/bin/agy-gui`, `$PREFIX/bin/agy-hub`, `$PREFIX/bin/agy-ui`, and `$PREFIX/bin/agy-service`.
3. **Cleans Runtime State**: Removes `hub.pid` and `hub.log`.
4. **Reverts DNS Tweaks**: Removes the `no-aaaa` entry from `$PREFIX/etc/resolv.conf`.
5. **Restores Upstream Binary**: Restores the embedded web assets inside `agy.va39` back to upstream defaults.
6. **Preserves Upstream CLI**: Steps 1, 2, and 3 (storage permissions, dependencies, and upstream terminal `agy` CLI binary & credentials) remain completely untouched and functional in your terminal.

---

## License & Legal Disclaimers

- **License**: Distributed under the [Apache License 2.0](LICENSE.md).
- **Disclaimer**: See [DISCLAIMER.md](DISCLAIMER.md) for limitation of liability and non-affiliation notices.
