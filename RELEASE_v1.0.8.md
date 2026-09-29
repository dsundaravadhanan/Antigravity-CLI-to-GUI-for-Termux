# Release Notes: Version 1.0.8

## Antigravity Local Web GUI for Android (Termux)

Version 1.0.8 introduces a patch for running Google's official Antigravity Local Web GUI directly inside Termux on Android. It bridges upstream Antigravity CLI release builds with customized mobile browser launcher utilities.

---

## What's New in v1.0.8

### 1. Browser-Based Local Web GUI
- Launches Google's official local web interface on `http://localhost:4400`.
- Requires zero desktop environments, X11 servers, or VNC viewers.
- Automated port polling detects when the internal web server is ready and opens your default Android browser directly to the chat and workspace.

### 2. In-Place Web Asset & Logo Patching
- Patches the embedded web bundle compiled inside `agy.va39` without altering the 209,080,504-byte file length or shifting ELF section offsets.
- Replaces the default `Jetski Web` title with `<title>Antigravity CLI</title>`.
- Replaces placeholder icon emojis with the Antigravity SVG logo.
- Adds `apple-touch-icon` metadata for clean Android home-screen progressive web app (PWA) shortcuts.
- Fully synchronizes the ZIP Streaming Data Descriptor (`PK\x07\x08`) and CRC32 checksums, ensuring complete compliance with Go's `archive/zip` validator.

### 3. Fast Network & IPv4 DNS Optimization
- Eliminates 15-second startup latency caused by cellular network IPv6 resolution issues on Android.
- Automatically and idempotently injects `options timeout:1 attempts:2 no-aaaa` into `$PREFIX/etc/resolv.conf`.

### 4. Dual Launch Utilities
- **`agy-gui`**: Foreground launcher that monitors server health, outputs live diagnostic logs to the terminal, and auto-launches Chrome.
- **`agy-service`**: Dedicated background daemon manager supporting `start`, `stop`, `status`, `restart`, and `logs`. Allows Termux to be minimized or closed while keeping the web session alive.
- Aliased symlinks for `agy-hub` and `agy-ui` included out of the box.

### 5. Automated Google OAuth Token Migration
- Scans Android device storage, Download folders, and local project directories for `antigravity-oauth-token`.
- Automatically copies and sets secure permissions (`600`) at `~/.gemini/antigravity-cli/antigravity-oauth-token`, allowing immediate authenticated access without repetitive browser logins.

### 6. Full Reversion & Uninstaller (`revert_gui.sh`)
- Completely removes all GUI launchers, background services, daemon logs, and network tweaks.
- Restores the embedded binary assets back to pristine upstream defaults.
- Leaves core Android storage access, glibc runtime, and upstream terminal `agy` CLI completely intact.

---

## Release Assets

- `install.sh`: Automated quick-install script.
- `patch_gui.sh`: Standalone Web GUI patcher for existing Antigravity CLI installations.
- `revert_gui.sh`: Clean uninstaller and upstream restoration utility.
