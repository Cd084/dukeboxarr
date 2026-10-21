# DukeBoxarr

An old-school touch-screen jukebox for a Plex music library. Browse album "title strips", tap a song or punch in its number, and it joins the queue. When the queue runs dry, an AI DJ, or genre-matched random play, keeps the music going.

It's built with Flutter. Windows is supported now; Android, Linux and iOS are planned. It's designed for a touch-screen laptop or a tablet connected to an amp.

---

## Features

### The jukebox screen
- **Album title strips:** cards show the number, cover, title, artist, year and track list, 4 per screen by default.
- **No scrolling:** if an album has more tracks than fit, it continues on more cards marked `1/2`, `2/2`, and so on.
- **Page flipping:** swipe, tap the ◀ ▶ buttons, or hold them to flip quickly. The arrow and PgUp/PgDn keys also work.
- **A–Z bar:** jump to artists by first letter (`#` for numbers and symbols).
- **Highlighting:** the song now playing is highlighted, and queued songs are marked on their cards.

### Choosing songs
- **Tap** any song on a card to queue it.
- **Selection codes:** every album has a 4-digit number, and each track a 2-digit number. Album `0123`, track `05` is code **`012305`**.
  - **Keypad pop-up:** live preview of the album or song as you type; SHOW ALBUM jumps the grid to it.
  - **Keypad strip** (optional): a 0–9 strip under the A–Z bar.
  - **Keyboard:** number keys and Enter type codes directly.
- **Search:** artists (tap to filter the grid), albums (tap to jump), or songs (tap to queue, codes shown).
- **Genre filter:** narrow the grid to one or more genres. Filtered views keep the albums' real numbers.
- **Playlists:** your Plex audio playlists, queued in order or shuffled.
  - Very large playlists (over 200 songs, e.g. "All Music") offer a random 25, 50 or 100 instead.
  - Empty smart playlists are hidden.

### The queue
- **First come, first served.** A request never interrupts the current song; it plays when that song ends.
- **No duplicates:** a song can't be queued twice, or while it's playing.
- **Next up:** the now-playing bar shows the next song, labelled *AI pick* or *random* when it isn't a request.
- **Queue screen:** the current song, the requests, then the lined-up AI or random picks. Each request has **BUMP** (make it play next) and **remove**, if allowed in Settings.

### Random play and the AI DJ
When the queue is empty, DukeBoxarr chooses the next song itself.
- **Genre random** (default): a random song weighted toward the genres of the last 15 plays. Songs people chose count 3× as much as random ones, so it follows the room rather than drifting.
- **AI DJ** (optional): a local model running in [Ollama](https://ollama.com) picks 5 songs that fit what people requested recently.
  - "Recently" is a window you choose in Settings: 1 to 24 hours. If nobody requested anything in that window, it follows whatever played.
  - It picks from a few hundred candidates in matching genres, skipping anything played recently.
  - It picks while the current song plays, so there's no gap. A new request makes it re-pick around that request.
  - If Ollama is slow or unreachable, DukeBoxarr falls back to genre random. The music never stops.

### Where the music plays
- **This device:** its speakers, or whatever it's plugged into.
- **A Plex player:** a Plex app on a TV or streamer, or Plexamp. DukeBoxarr stays in charge of the queue:
  - It tells the player which song to play and checks its progress every second to know when the song ends.
  - Pause and skip control the player.
  - If the player stops responding, playback switches back to this device and a warning appears in the top bar.

### Plex integration
- **Sign-in:** through plex.tv/link (DukeBoxarr gets its own revocable device token), or paste a token.
- **Library cache:** a local copy for instant start-up, and it can re-sync automatically. The old library stays usable during a sync, and a failed sync never damages it.
- **Fixed numbers:** album numbers stay the same as your library grows.
  - New albums get the next free numbers.
  - "Renumber" (in Settings) re-sorts everything A–Z.
  - Numbers are reset automatically if DukeBoxarr is pointed at a different Plex server.
- **Shows up in Plex** (optional):
  - Plays on this device appear in the Plex Dashboard and Tautulli as **"DukeBoxarr (*computer name*)"**.
  - Songs that play to the end count as plays.

### Kiosk-friendly
- **Settings PIN:** guests can't change anything without it.
- **Guest controls:** delete, skip and bump each have their own switch.

---

## Selection numbers and singles

Many libraries contain thousands of one-track "albums" (loose singles). Giving each its own number would bury the real albums, so DukeBoxarr groups them:

| Release | How it appears |
|---|---|
| Album with **4+ tracks** | Its own number, e.g. `0123 · Black Dog Barking` |
| Singles/EPs by an artist with **3+ loose tracks** | One card per artist: `0456 · Singles & EPs — AC/DC` |
| Everyone else's loose tracks | Packed alphabetically into shared cards: `0789 · Singles · A–B` (20 songs each) |
| Album with **over 99 tracks** | Split into numbered parts: `(Part 1)`, `(Part 2)` |

All three thresholds can be changed in Settings → Catalogue numbering.

---

## Settings

Open with the ⚙ button. If a PIN is set, it's asked for first.

### Plex server
| Setting | What it does |
|---|---|
| Server URL | Your Plex server, e.g. `http://192.168.1.10:32400`. Use the plain `http://` LAN address. |
| Music library | Name of the Plex music library to use (default `Music`) |
| Plex token / Sign in with Plex | Paste a token, or tap **Sign in with Plex** and enter the code shown at **plex.tv/link** |
| Save & connect | Tests the connection and saves |
| Re-sync library | Re-reads the whole library from Plex now |

### Queue
| Setting | Default | What it does |
|---|---|---|
| Allow removing songs from the queue | On | Shows the remove button in the queue |
| Allow skipping the current song | On | Shows the skip button |
| Allow bumping a queued song to the top | On | Shows **BUMP** in the queue |
| Random play when the queue is empty | On | Keeps music playing when nothing is requested |

### AI DJ (Ollama)
| Setting | Default | What it does |
|---|---|---|
| Use AI for random play | Off | The AI picks the random songs. Needs Ollama. |
| Ollama URL | `http://localhost:11434` | Where Ollama runs |
| Load models / Model | none | Lists the models installed in Ollama so you can choose one. See [Choosing an AI model](#choosing-an-ai-model). |
| Follow songs requested in the last | 3 h | 1, 2, 3, 6, 12 or 24 hours of requests steer the AI |

The last AI error, if any, is shown in this section.

### Library sync
| Setting | Default | What it does |
|---|---|---|
| Automatically re-sync with Plex every | 24 h | Off, 6 h, 12 h, 24 h, 3 days or 7 days. Checked a minute after start-up, then every 15 minutes. |

### Output
| Setting | Default | What it does |
|---|---|---|
| Play music on | This device | **This device** or a Plex player. Tap **Find Plex players** to search; the Plex app must be open on the player. |
| Report playback to Plex | On | Shows DukeBoxarr in the Plex Dashboard and Tautulli, and updates play counts. Plays count toward the signed-in Plex user. |

### Security
| Setting | Default | What it does |
|---|---|---|
| Settings PIN | Off | 4–8 digits, entered twice. **Set PIN**, **Change PIN** or **Remove**. |

### Display
| Setting | Default | What it does |
|---|---|---|
| Show number keypad under the A–Z bar | Off | Always-visible 0–9 strip with code display, **GO** (show album) and **SELECT** |
| Album cards per screen | 4 | 2–6. In landscape, 5–6 cards use two rows; in portrait, 3+ cards use two rows. |

### Catalogue numbering
| Setting | Default | What it does |
|---|---|---|
| Releases with fewer tracks than this count as singles | 4 | Below this, a release is grouped with singles instead of getting its own number |
| Artists with this many singles get their own card | 3 | Otherwise their singles go into shared "Singles · A–B" cards |
| Songs per shared "Singles" card | 20 | 10–40 |
| Renumber all albums | — | Re-sorts all numbers A–Z. Printed or remembered codes will change. |

### Choosing an AI model

The AI DJ needs a small, fast, non-reasoning model that follows instructions well and knows music. DukeBoxarr switches off "thinking" for models that support it. Big reasoning models are slower and pick no better.

**Recommended**
| Model | Size on GPU | Why |
|---|---|---|
| **`qwen3.5:4b`** ⭐ | ~3–4 GB | Best picks in testing, and the fastest. The default choice. |
| `qwen3.5:9b` | ~6–7 GB | Also good, a little slower. A fine choice if you already have it, e.g. shared with [B-Side](https://github.com/Cd084/B-Side). |
| `llama3.1:8b` | ~5–6 GB | Usable. Leans toward classic rock and chart hits. |

**Not recommended**
- `gemma4:e4b` and `qwen2.5:7b-instruct` returned valid picks, but often off-style (pop songs after a hard-rock request).
- 27B+ and reasoning models (e.g. `deepseek-r1`) are much slower, with no better results for this job.

**Test results:** one run per model, three Airbourne songs as the requests, candidates all tagged just "Pop/Rock" by Plex. Plex genres are broad, so the model's own music knowledge decides the fit.

| Model | Time (model loaded) | Picks |
|---|---|---|
| qwen3.5:4b | ~10 s | Metallica, AC/DC, Halestorm, Sum 41, Green Day |
| qwen3.5:9b | ~14 s | AC/DC ×2, Guns N' Roses, Airbourne (live), Arctic Monkeys |
| llama3.1:8b | ~13 s | Springsteen, Def Leppard ×2, Whitesnake, AC/DC |
| qwen2.5:7b-instruct | ~14 s | Tina Turner, KISS, Elton John, AC/DC, Joe Cocker |
| gemma4:e4b | ~10 s | Lenny Kravitz, Harry Styles, Sabrina Carpenter, Shawn Mendes, Kim Wilde |

**Notes**
- Times are from an older 2× Nvidia P40 server.
- The first request after the model has been unloaded takes 20–50 s longer while Ollama loads it. DukeBoxarr keeps the model loaded for 30 minutes after each use.
- DukeBoxarr picks during the current song, so any model that answers in well under a song's length is fine.
- Install a model with `ollama pull qwen3.5:4b`, then choose it under Settings → AI DJ → Load models.

You can compare models on your own library with the live test (see [Building](#building)).

---

## Tips

- **Use a separate Plex user for DukeBoxarr.** Create a Plex Home or managed user (e.g. "Jukebox") and sign DukeBoxarr in as it. Guests' plays then stay out of your own history and recommendations, and Tautulli can mute notifications for just that user.
- **A Plex player isn't found:**
  1. Open Plex on the device first, signed in to the same account.
  2. Make sure it allows remote control ("Advertise as player").
  3. On the server, check that Settings → Network → *Enable local network discovery (GDM)* is on.
- **Forgot the Settings PIN:** close DukeBoxarr and delete the `flutter.adminPin` line from `%APPDATA%\ca.dukebox\dukebox\shared_preferences.json`.
- **Where data lives (Windows):**
  - Settings: `%APPDATA%\ca.dukebox\dukebox\shared_preferences.json`
  - Library cache and album numbers: `%APPDATA%\ca.dukebox\dukebox\dukebox\` (`library.json`, `numbers.json`)
  - These folders, and the package id `ca.dukebox`, still use the project's original name "dukebox". Changing them would lose existing settings and album numbers.

---

## Building

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install). For Windows builds you also need Visual Studio 2022, or its Build Tools, with the C++ desktop workload. Audio playback uses [media_kit](https://pub.dev/packages/media_kit) (libmpv), which is downloaded during the build.

```sh
flutter run -d windows               # run in debug mode (press r to hot reload)
flutter build windows --release      # build to build\windows\x64\runner\Release\dukeboxarr.exe
flutter test                         # unit tests
```

There's an optional live test of the AI DJ against your own Ollama and cached library:

```powershell
$env:DUKEBOX_LIVE=1; $env:OLLAMA_URL='http://<ollama-host>:11434'; $env:AI_MODEL='qwen3.5:9b'; $env:SEED_ARTIST='AC/DC'
flutter test test/ai_dj_live_test.dart
```

### Project layout
| Path | Purpose |
|---|---|
| `lib/plex_client.dart` | Plex server and plex.tv API: library, playlists, players, sign-in, progress reports |
| `lib/library.dart` | Library cache, auto-sync, catalogue numbering and singles grouping |
| `lib/jukebox.dart` | Queue, playback, random/AI look-ahead, history, Plex reporting |
| `lib/ai_dj.dart` | Ollama song picker |
| `lib/output.dart` | Outputs: this device (media_kit) and remote Plex player |
| `lib/settings.dart` | All settings and their defaults |
| `lib/ui/` | Screens: grid, cards, keypad, search, playlists, queue, settings, PIN |
