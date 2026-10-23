import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'models.dart';
import 'plex_client.dart';

/// Where the music comes out: this device ([LocalOutput]) or a Plex player
/// on the network ([PlexRemoteOutput]).
abstract class AudioOutput {
  String get name;
  Stream<bool> get completed;
  Stream<String> get errors;
  Stream<bool> get playing;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Future<void> play(Song song, String streamUrl);

  /// Whether [playOverlapped] is supported (song overlap / radio-style segue).
  bool get supportsOverlap => false;

  /// Starts [song] while the current one is still ending, fading the ending
  /// song out over [fade]. Outputs without overlap just [play].
  Future<void> playOverlapped(Song song, String streamUrl, Duration fade) => play(song, streamUrl);

  Future<void> togglePause();
  Future<void> stop();
  Future<void> setVolume(double percent);
  Future<void> dispose();
}

/// Plays on this device with media_kit. For song overlap it runs a second
/// player: the new song starts on it at full volume while the old player
/// fades out and is then disposed. The streams always follow the newest
/// player, so the old one's "completed" never advances the queue twice.
class LocalOutput extends AudioOutput {
  mk.Player _p = mk.Player();
  final _fading = <mk.Player>{};
  final _subs = <StreamSubscription>[];
  double _volume = 100;

  final _completed = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();

  LocalOutput() {
    _follow(_p);
  }

  void _follow(mk.Player p) {
    for (final s in _subs) {
      s.cancel();
    }
    _subs
      ..clear()
      ..addAll([
        p.stream.completed.where((c) => c).listen(_completed.add),
        p.stream.error.listen(_errors.add),
        p.stream.playing.listen(_playing.add),
        p.stream.position.listen(_position.add),
        p.stream.duration.listen(_duration.add),
      ]);
  }

  @override
  String get name => 'This device';
  @override
  Stream<bool> get completed => _completed.stream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;

  @override
  Future<void> play(Song song, String streamUrl) => _p.open(mk.Media(streamUrl), play: true);

  @override
  bool get supportsOverlap => true;

  @override
  Future<void> playOverlapped(Song song, String streamUrl, Duration fade) async {
    final old = _p;
    final next = mk.Player();
    await next.setVolume(_volume);
    _p = next;
    _follow(next);
    await next.open(mk.Media(streamUrl), play: true);
    _fadeOut(old, fade);
  }

  /// Fades a player out (eased, so the end isn't abrupt), then disposes it.
  Future<void> _fadeOut(mk.Player p, Duration fade) async {
    _fading.add(p);
    const steps = 25;
    for (var i = 1; i <= steps && _fading.contains(p); i++) {
      await Future.delayed(fade ~/ steps);
      final left = 1 - i / steps;
      if (_fading.contains(p)) await p.setVolume(_volume * left * left);
    }
    if (_fading.remove(p)) await p.dispose();
  }

  Future<void> _stopFading() async {
    final players = _fading.toList();
    _fading.clear();
    for (final p in players) {
      await p.dispose();
    }
  }

  @override
  Future<void> togglePause() async {
    // Pausing mid-overlap: drop the ending song rather than leave it hanging.
    await _stopFading();
    await _p.playOrPause();
  }

  @override
  Future<void> stop() async {
    await _stopFading();
    await _p.stop();
  }

  @override
  Future<void> setVolume(double percent) {
    _volume = percent;
    return _p.setVolume(percent);
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _stopFading();
    await _p.dispose();
    for (final c in [_completed, _errors, _playing, _position, _duration]) {
      await c.close();
    }
  }
}

/// Plays on a Plex player (TV app, streamer, Plexamp) via the Plex remote
/// control API. DukeBoxarr stays in charge of the queue: each song is sent as a
/// one-song play queue, and the player's timeline is polled to know when it
/// has finished.
class PlexRemoteOutput extends AudioOutput {
  final PlexClient server;
  final String serverId; // machineIdentifier of the Plex server
  final PlexPlayer player;

  PlexRemoteOutput(this.server, this.serverId, this.player);

  final _completed = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();

  int _commandId = 0;
  String? _base; // control URL that last worked
  Timer? _poll;
  bool _polling = false;
  String? _songKey;
  bool _sawPlaying = false;
  bool _isPlaying = false;
  int _misses = 0;

  @override
  String get name => player.name;
  @override
  Stream<bool> get completed => _completed.stream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;

  Map<String, String> get _headers => {
        ...PlexClient.headers(server.clientId, server.token),
        'X-Plex-Target-Client-Identifier': player.id,
        'X-Plex-Device-Name': 'DukeBoxarr',
      };

  /// Sends a command to the player: directly if possible, otherwise through
  /// the Plex server, which relays to players it knows about.
  Future<String> _send(String path, [Map<String, String> params = const {}]) async {
    final q = {...params, 'commandID': '${++_commandId}'};
    final bases = {?_base, ...player.uris, server.baseUrl};
    Object? lastError;
    for (final b in bases) {
      try {
        final res = await http
            .get(Uri.parse('$b$path').replace(queryParameters: q), headers: _headers)
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          _base = b;
          return utf8.decode(res.bodyBytes);
        }
        lastError = 'HTTP ${res.statusCode}';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('${player.name} did not respond ($lastError)');
  }

  @override
  Future<void> play(Song song, String streamUrl) async {
    _stopPolling();
    _songKey = song.key;
    _sawPlaying = false;
    try {
      final queueId = await server.createPlayQueue(song.key, serverId);
      final u = Uri.parse(server.baseUrl);
      await _send('/player/playback/playMedia', {
        'key': '/library/metadata/${song.key}',
        'offset': '0',
        'type': 'music',
        'machineIdentifier': serverId,
        'protocol': u.scheme,
        'address': u.host,
        'port': '${u.hasPort ? u.port : (u.scheme == 'https' ? 443 : 80)}',
        'token': server.token,
        'containerKey': '/playQueues/$queueId?own=1&window=200',
      });
      _startPolling();
    } catch (e) {
      _errors.add('$e');
    }
  }

  void _startPolling() {
    _misses = 0;
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _tick() async {
    if (_polling) return;
    _polling = true;
    try {
      final t = musicTimeline(await _send('/player/timeline/poll', {'wait': '0'}));
      _misses = 0;
      if (t == null) return;
      final state = t['state'] ?? 'stopped';
      final time = int.tryParse(t['time'] ?? '') ?? 0;
      final dur = int.tryParse(t['duration'] ?? '') ?? 0;
      final key = t['ratingKey'];
      _position.add(Duration(milliseconds: time));
      if (dur > 0) _duration.add(Duration(milliseconds: dur));
      final nowPlaying = state == 'playing';
      if (nowPlaying != _isPlaying) _playing.add(_isPlaying = nowPlaying);
      if (nowPlaying || state == 'buffering') _sawPlaying = true;

      // Finished: it was playing our song and has now stopped (or moved on).
      final movedOn = key != null && _songKey != null && key != _songKey;
      if (_sawPlaying && (state == 'stopped' || movedOn)) {
        _stopPolling();
        _completed.add(true);
      }
    } catch (e) {
      if (++_misses == 10) {
        _stopPolling();
        _errors.add('Lost contact with ${player.name}: $e');
      }
    } finally {
      _polling = false;
    }
  }

  /// Extracts the music `<Timeline>` attributes from a timeline poll reply,
  /// which players send as XML (or occasionally JSON).
  @visibleForTesting
  static Map<String, String>? musicTimeline(String body) {
    try {
      final j = jsonDecode(body);
      for (final t in (j['MediaContainer']?['Timeline'] as List? ?? const [])) {
        if (t['type'] == 'music') return {for (final e in (t as Map).entries) '${e.key}': '${e.value}'};
      }
      return null;
    } catch (_) {}
    for (final m in RegExp(r'<Timeline\b([^>]*)/?>').allMatches(body)) {
      final attrs = {
        for (final a in RegExp(r'(\w+)="([^"]*)"').allMatches(m.group(1)!)) a.group(1)!: a.group(2)!,
      };
      if (attrs['type'] == 'music') return attrs;
    }
    return null;
  }

  @override
  Future<void> togglePause() async {
    try {
      await _send(_isPlaying ? '/player/playback/pause' : '/player/playback/play', {'type': 'music'});
    } catch (e) {
      _errors.add('$e');
    }
  }

  @override
  Future<void> stop() async {
    _stopPolling();
    _songKey = null;
    try {
      await _send('/player/playback/stop', {'type': 'music'});
    } catch (e) {
      debugPrint('remote stop failed: $e');
    }
    _playing.add(_isPlaying = false);
  }

  @override
  Future<void> setVolume(double percent) async {
    try {
      await _send('/player/playback/setParameters', {'volume': '${percent.round()}', 'type': 'music'});
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _stopPolling();
    for (final c in [_completed, _errors, _playing, _position, _duration]) {
      await c.close();
    }
  }
}
