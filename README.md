# Clipps

Clipps is a Windows clipboard manager. It saves what you copy, lets you search it, and keeps it in groups, tags and tasks.

## Where your data lives

- Clips: `%APPDATA%\Clipps\clipps\clipps.db`
- Daily backups (newest 7): `%APPDATA%\Clipps\clipps\backups\`
- A copy made once before the v3 upgrade: `backups\clipps-pre-v3.db`

## Restore from a backup

1. Quit Clipps from the tray icon (right-click, then Quit).
2. In `%APPDATA%\Clipps\clipps\`, delete `clipps.db-wal` and `clipps.db-shm` if they exist.
3. Copy `backups\clipps-YYYY-MM-DD.db` over `clipps.db`.
4. Start Clipps.
