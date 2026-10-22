# Changelog

DukeBoxarr's version lives in `pubspec.yaml` (`version: X.Y.Z+build`). Each release gets a git tag `vX.Y.Z` and an installer built with `tool\build_installer.ps1`.

## 0.10.0 — 2026-10-21

- **Ubuntu 24.04+ support:** a .deb package (`tool/build_linux.sh`, or `tool/build_linux_wsl.ps1` from Windows) with an app-menu entry and a `dukeboxarr` command.
- **Automated releases:** pushing a `vX.Y.Z` tag builds the Windows installer and the Ubuntu .deb on GitHub and attaches them to the release.

## 0.9.0 — 2026-10-21

The first versioned release.

- **Jukebox grid:** album title strips with no scrolling (long albums continue on more cards), A–Z jump, swipe and hold-to-flip.
- **Selection codes:** 4-digit album + 2-digit track. Use the pop-up keypad, the optional on-screen keypad strip, or the keyboard.
- **Queue:** first come, first served. Requests never interrupt the current song. Bump to top, remove, skip; each can be switched off.
- **Random play:** genre-weighted from recent plays, or the **AI DJ** (Ollama), steered by requests from the last 1–24 hours.
- **Search, genre filter and Plex playlists:** large playlists offer a random sample.
- **Output:** this device or a Plex player (TV, streamer, Plexamp), with automatic fallback to this device.
- **Plex:** plex.tv/link sign-in, cached library with auto-sync, stable album numbers, and playback reported to the Plex Dashboard and Tautulli.
- **Settings PIN** for kiosk use.
- **Windows installer:** per-user install, Start Menu and optional desktop shortcut, in-place upgrades.
