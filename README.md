# Dukebox

An old-school touch-screen jukebox for a Plex music library. Built with Flutter: Windows first, with Android, Linux and iOS to follow.

- An album grid of jukebox title-strip cards, with no scrolling. Long albums continue on additional cards.
- Pick songs by tapping, or on the keypad with a 4-digit album number plus a 2-digit track number (`012305`).
- A first-in, first-out queue. New requests wait for the current song to finish.
- When the queue is empty, random play picks songs weighted toward the genres of recent plays.
- Search, genre filter, and A–Z jump.
- Loose singles are grouped by artist so the numbering stays compact.

## Run

```
flutter run -d windows
```

On first launch, enter your Plex server URL, then either sign in with plex.tv/link or paste a token.
