import 'package:audio_service/audio_service.dart';

import 'jukebox.dart';
import 'settings.dart';

/// Connects the jukebox to the system's media session (audio_service).
///
/// On Android this runs playback in a media playback service with a
/// "now playing" notification, so Android keeps DukeBoxarr running, and keeps
/// its network, while the screen is locked (otherwise Doze cuts the network,
/// songs fail to load and playback stops). It also gives play/pause/skip on
/// the lock screen, in the notification and from Bluetooth/headset buttons.
/// On iOS it provides the lock-screen controls.
class JukeboxAudioHandler extends BaseAudioHandler {
  final Jukebox jukebox;
  final Settings settings;

  JukeboxAudioHandler(this.jukebox, this.settings) {
    jukebox.addListener(_sync);
    settings.addListener(_sync);
    _sync();
  }

  String? _shownKey;

  void _sync() {
    final cur = jukebox.current;
    if (cur?.song.key != _shownKey) {
      _shownKey = cur?.song.key;
      if (cur == null) {
        mediaItem.add(null);
      } else {
        final album = jukebox.library.albums[cur.song.albumKey];
        final art = jukebox.library.client.artUrl(album?.thumb, size: 512);
        mediaItem.add(MediaItem(
          id: cur.song.key,
          title: cur.song.title,
          artist: cur.song.artist,
          album: album?.title,
          duration: Duration(milliseconds: cur.song.durationMs),
          artUri: art == null ? null : Uri.parse(art),
        ));
      }
    }

    final canSkip = settings.allowSkip && cur != null;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        jukebox.active ? MediaControl.pause : MediaControl.play,
        if (canSkip) MediaControl.skipToNext,
      ],
      androidCompactActionIndices: [0, if (canSkip) 1],
      processingState: cur == null ? AudioProcessingState.idle : AudioProcessingState.ready,
      // "Playing" includes the gap while the next song loads; reporting a pause
      // there would let Android drop the service and cut the network.
      playing: jukebox.active,
      updatePosition: jukebox.progress.value.$1,
    ));
  }

  @override
  Future<void> play() async {
    if (!jukebox.active) await jukebox.togglePause();
  }

  @override
  Future<void> pause() async {
    if (jukebox.active && jukebox.playing) await jukebox.togglePause();
  }

  @override
  Future<void> skipToNext() async => jukebox.skip();

  // A jukebox doesn't "stop": the system's stop (e.g. swiping the
  // notification away while paused) just keeps it paused.
  @override
  Future<void> stop() => pause();
}
