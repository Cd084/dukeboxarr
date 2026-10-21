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
  Future<void> togglePause();
  Future<void> stop();
  Future<void> setVolume(double percent);
  Future<void> dispose();
}

class LocalOutput implements AudioOutput {
  final mk.Player _p = mk.Player();

  @override
  String get name => 'This device';
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
  Future<void> play(Song song, String streamUrl) => _p.open(mk.Media(streamUrl), play: true);
  @override
  Future<void> togglePause() => _p.playOrPause();
  @override
  Future<void> stop() => _p.stop();
  @override
  Future<void> setVolume(double percent) => _p.setVolume(percent);
  @override
  Future<void> dispose() => _p.dispose();
}

/// Plays on a Plex player (TV app, streamer, Plexamp) via the Plex remote
/// control API. Dukebox stays in charge of the queue: each song is sent as a
/// one-song play queue, and the player's timeline is polled to know when it
/// has finished.
class PlexRemoteOutput implements AudioOutput {
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
        'X-Plex-Device-Name': 'Dukebox',
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
