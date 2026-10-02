# Antigravity Web GUI for Termux v1.0.9

### What's Changed
- **Fixed blank black/white page on startup**: Added dynamic CRC patch for `main.js` web bundle when corrupted by upstream VA39 build.
- **Fixed Web GUI reset after `agy update`**: Added automatic post-update hook in `$PREFIX/bin/agy` so running `agy update` auto-patches the GUI without manual steps.
- **Fixed ZIP integrity & offset shifts**: Rewrote in-place `index.html` patch to use proper extra-field padding so subsequent asset offsets and CRCs are never broken.
- **Skip on branding**: If title/logo patch fails or exceeds size limits on future Google web bundles, it skips instead of failing the server.
- **Improved uninstaller**: `revert_gui.sh` now removes CLI wrappers cleanly and preserves all chat history/tokens in `~/.gemini/antigravity-cli`.

### Troubleshooting
- **Blank page persists after patching**: Clear Chrome browsing cache (**History** > **Clear browsing data** > select **Cached images and files**) or open `http://localhost:4400` in an Incognito tab to clear stale cached scripts.
- **Session state / port in use**: Restart the Termux session or run `killall agy 2>/dev/null` before running `agy-gui`.

### Release Assets
- `install.sh`: One-line installer with auto-update hook.
- `patch_gui.sh`: Post-install patcher with dynamic asset repair.
- `revert_gui.sh`: Clean uninstaller that restores stock binary.
