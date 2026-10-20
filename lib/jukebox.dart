import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library.dart';
import 'models.dart';
import 'output.dart';
import 'settings.dart';

/// Queue + playback logic.
///
/// Requested tracks play first-in-first-out. When the queue is empty and
/// random play is on, a random track is chosen, weighted toward the genres of
/// recently played tracks. A newly requested track never interrupts the
/// current song: it plays when the current (random or requested) one ends.
class Jukebox extends ChangeNotifier {
  final Library library;
  final Settings settings;
  final AudioOutput output;
  final _rng = Random();

  final List<QueueItem> queue = [];
  QueueItem? current;
  bool playing = false;

  /// (position, duration) — separate so ticks don't rebuild the grid.
  final progress = ValueNotifier<(Duration, Duration)>((Duration.zero, Duration.zero));

  /// Most recent first. (songKey, wasRandom)
  final List<(String, bool)> _history = [];
  static const _historyMax = 300;

  Map<String, List<Song>>? _genreIndex;
  int _consecutiveErrors = 0;
  final _subs = <StreamSubscription>[];

  Jukebox(this.library, this.settings, this.output) {
    library.addListener(() => _genreIndex = null);
    _subs.addAll([
      output.completed.listen((_) => next()),
      output.errors.listen(_onError),
      output.playing.listen((p) => _update(() => playing = p)),
      output.position.listen((p) => progress.value = (p, progress.value.$2)),
      output.duration.listen((d) => progress.value = (progress.value.$1, d)),
    ]);
    _loadHistory();
  }

  bool get idle => current == null;

  /// Adds a requested track. Starts playback if nothing is playing.
  void request(Song song) {
    queue.add(QueueItem(song, library.entryOf(song)));
    if (current == null) {
      next();
    } else {
      notifyListeners();
    }
  }

  bool isQueued(Song s) => queue.any((q) => q.song.key == s.key);

  void removeAt(int i) {
    if (!settings.allowDelete || i < 0 || i >= queue.length) return;
    queue.removeAt(i);
    notifyListeners();
  }

  void skip() {
    if (settings.allowSkip) next();
  }

  Future<void> togglePause() async {
    if (current == null) {
      await next();
    } else {
      await output.togglePause();
    }
  }

  /// Advances to the next requested track, or a random one.
  Future<void> next() async {
    QueueItem? item;
    if (queue.isNotEmpty) {
      item = queue.removeAt(0);
    } else if (settings.randomWhenEmpty) {
      final s = _pickRandom();
      if (s != null) item = QueueItem(s, library.entryOf(s), random: true);
    }
    current = item;
    progress.value = (Duration.zero, Duration.zero);
    notifyListeners();
    if (item == null) {
      await output.stop();
      return;
    }
    _remember(item);
    await output.play(library.client.streamUrl(item.song.partKey));
  }

  void _onError(String e) {
    debugPrint('playback error: $e');
    if (++_consecutiveErrors > 5) {
      current = null;
      notifyListeners();
      return;
    }
    Future.delayed(const Duration(seconds: 1), next);
  }

  // ------------------------------------------------------------ random play

  Song? _pickRandom() {
    final all = library.songs.values.toList(growable: false);
    if (all.isEmpty) return null;
    final recent = {for (final h in _history) h.$1};

    // Weight genres from the last 15 plays; tracks people chose count 3x,
    // so random play follows the room rather than drifting on its own.
    final weights = <String, double>{};
    for (final (key, wasRandom) in _history.take(15)) {
      final s = library.songs[key];
      if (s == null) continue;
      final g = library.genresOf(s);
      for (final name in g) {
        weights[name] = (weights[name] ?? 0) + (wasRandom ? 1 : 3) / g.length;
      }
    }

    List<Song> pool = all;
    if (weights.isNotEmpty) {
      final index = _genreIndex ??= _buildGenreIndex();
      var r = _rng.nextDouble() * weights.values.fold(0.0, (a, b) => a + b);
      for (final MapEntry(key: g, value: w) in weights.entries) {
        if ((r -= w) <= 0) {
          pool = index[g] ?? all;
          break;
        }
      }
    }
    for (var i = 0; i < 30; i++) {
      final s = pool[_rng.nextInt(pool.length)];
      if (!recent.contains(s.key)) return s;
    }
    return all[_rng.nextInt(all.length)];
  }

  Map<String, List<Song>> _buildGenreIndex() {
    final idx = <String, List<Song>>{};
    for (final s in library.songs.values) {
      for (final g in library.genresOf(s)) {
        (idx[g] ??= []).add(s);
      }
    }
    return idx;
  }

  // --------------------------------------------------------------- history

  void _remember(QueueItem item) {
    _consecutiveErrors = 0;
    _history.insert(0, (item.song.key, item.random));
    if (_history.length > _historyMax) _history.removeLast();
    SharedPreferences.getInstance().then((p) => p.setStringList(
        'history', [for (final (k, r) in _history) '${r ? 'r' : 'q'}$k']));
  }

  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    for (final h in p.getStringList('history') ?? const <String>[]) {
      _history.add((h.substring(1), h[0] == 'r'));
    }
  }

  void _update(VoidCallback f) {
    f();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    output.dispose();
    super.dispose();
  }
}
