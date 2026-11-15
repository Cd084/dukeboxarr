# Changelog

DukeBoxarr's version lives in `pubspec.yaml` (`version: X.Y.Z+build`). Each release gets a git tag `vX.Y.Z` and an installer built with `tool\build_installer.ps1`.

## Unreleased

- **Android: the stream keeps going with the screen off.** While music plays, DukeBoxarr now holds a wake lock and a Wi-Fi lock (like Plexamp/Spotify), so a real tablet's Wi-Fi no longer dozes and drops the connection to Plex. Both are released when paused or when the queue ends.
- **Settings → Background playback (Android):** shows whether Android restricts DukeBoxarr's battery use, with an **Allow** button for Android's own prompt to make it unrestricted. It also lists the extra Samsung settings to check.

## 0.13.0 — 2026-11-15

- **Android: keeps playing with the screen locked.** Playback now runs as a media playback service (audio_service), with a "now playing" notification and play/pause/skip on the lock screen, in the notification shade and from Bluetooth/headset buttons (also on iPad). Android previously cut DukeBoxarr's network in Doze, so songs failed to load and the queue was skipped empty.
- **Network trouble no longer empties the queue:** a song that fails to load is retried 3 times. If Plex can't be reached, playback stops with a message and the queue is kept, with failed requests back in front.

- **iPad / iPhone (iOS 15+):** an unsigned `.ipa` is built for each release, to install by sideloading with SideStore or AltStore. The app is set up to allow plain-http connections to Plex and Ollama on the home network, ask for local-network access, and keep playing in the background. Plex shows the device by its name.

## 0.12.0 — 2026-10-23

- **Song overlap** (Settings → Queue): 0–12 seconds, off by default. The next song starts that long before the current one ends, while the ending song fades out, radio-style. Applies when playing on this device; skipping still cuts straight away.
- The Android APK is now built and signed by the release workflow and attached to each release.

## 0.11.0 — 2026-10-22

- **Android app (Android 15+):** a signed APK (`tool/build_android.ps1`). Tested on an Android 15 tablet emulator: setup, library sync, browsing and playback.
- **Keep the screen on** setting (on by default): stops a tablet or PC from sleeping while DukeBoxarr is open.
- On Android, Plex shows the device as its model name (e.g. "DukeBoxarr (Google Pixel Tablet)").

## 0.10.2 — 2026-10-22

- **Shared playlists:** the Playlists screen also lists other Plex Home users' playlists, in a section per user. Each playlist is read with its owner's access. This can be turned off in Settings → Display.
- **Full screen:** Settings → Display → Full screen, remembered between launches. F11 toggles it unless a Settings PIN is set.

## 0.10.1 — 2026-10-21

- **Plex Home users:** Settings → Switch user lists your Home users (asking for a PIN where one is set). DukeBoxarr then browses and plays as that user, so restrictions and play history follow them. The account sign-in is kept, so switching doesn't need a new sign-in.

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
