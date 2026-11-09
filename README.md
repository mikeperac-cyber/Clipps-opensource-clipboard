# Clipps

Clipps remembers everything you copy on Windows, so you can find it again in two keystrokes.

## Features

- History with search and a date filter.
- Press `Ctrl+Alt+.`, type, then press `Enter` to copy the top match. `Esc` hides Clipps.
- Pin clips, sort them into groups, and add tags. Links, emails, phone numbers and code are tagged for you.
- Tasks, and notes on any clip.
- Trash with 15 days to restore.
- Light and dark theme.
- Pause capture from the sidebar or the tray menu.
- A "Duplicate" marker on clips whose text is saved more than once.
- Export your clips to CSV from the About dialog. The file goes to your Downloads folder.
- Skips content that password managers mark as private.
- Daily backups, keeping the newest 7.

## Privacy

Clipps works offline. Your clips are stored only on this PC and are never sent anywhere.

There is no account. Clipps does not use an internet connection. There are no analytics.

## Requirements

Windows 10 or 11, 64-bit. Clipps installs per user and does not need admin rights.

## Install and uninstall

Run `Clipps-Setup-3.3.0.exe`.

Uninstalling keeps your clips in `%APPDATA%\Clipps\clipps\`.

## Where your data lives

- Clips: `%APPDATA%\Clipps\clipps\clipps.db`
- Daily backups (newest 7): `%APPDATA%\Clipps\clipps\backups\`
- A copy made once before the v3 upgrade: `backups\clipps-pre-v3.db`

## Restore from a backup

1. Quit Clipps from the tray icon (right-click, then Quit).
2. In `%APPDATA%\Clipps\clipps\`, delete `clipps.db-wal` and `clipps.db-shm` if they exist.
3. Copy `backups\clipps-YYYY-MM-DD.db` over `clipps.db`.
4. Start Clipps.
