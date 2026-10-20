import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;

/// Where the music comes out. [LocalOutput] plays on this device; a remote
/// Plex-player output can implement the same interface later.
abstract class AudioOutput {
  Stream<bool> get completed;
  Stream<String> get errors;
  Stream<bool> get playing;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Future<void> play(String url);
  Future<void> togglePause();
  Future<void> stop();
  Future<void> setVolume(double percent);
  Future<void> dispose();
}

class LocalOutput implements AudioOutput {
  final mk.Player _p = mk.Player();

  @override
  Stream<bool> get completed => _p.stream.completed.where((c) => c);
  @override
  Stream<String> get errors => _p.stream.error;
  @override
  Stream<bool> get playing => _p.stream.playing;
  @override
  Stream<Duration> get position => _p.stream.position;
  @override
  Stream<Duration> get duration => _p.stream.duration;

  @override
  Future<void> play(String url) => _p.open(mk.Media(url), play: true);
  @override
  Future<void> togglePause() => _p.playOrPause();
  @override
  Future<void> stop() => _p.stop();
  @override
  Future<void> setVolume(double percent) => _p.setVolume(percent);
  @override
  Future<void> dispose() => _p.dispose();
}
