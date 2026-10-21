import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_dj.dart';
import 'library.dart';
import 'models.dart';
import 'output.dart';
import 'settings.dart';

/// Queue + playback logic.
///
/// Requested tracks play first-in-first-out. When the queue is empty and
/// random play is on, the next song comes from [upcoming]: songs picked ahead
/// of time by the AI DJ (steered by recent requests) or, without AI, a
/// genre-weighted random pick. A newly requested track never interrupts the
/// current song: it plays when the current (random or requested) one ends.
class Jukebox extends ChangeNotifier {
  final Library library;
  final Settings settings;
  final AudioOutput output;
  final AiDj ai;
  final _rng = Random();

  final List<QueueItem> queue = [];
  QueueItem? current;
  bool playing = false;

  /// Random/AI songs lined up for when the queue runs dry.
  final List<QueueItem> upcoming = [];
  bool aiBusy = false;
  String? aiError;
  int _refillGen = 0;

  /// (position, duration) — separate so ticks don't rebuild the grid.
  final progress = ValueNotifier<(Duration, Duration)>((Duration.zero, Duration.zero));

  /// Most recent first.
  final List<({String key, bool random, DateTime at})> _history = [];
  static const _historyMax = 500;

  Map<String, List<Song>>? _genreIndex;
  int _consecutiveErrors = 0;
  final _subs = <StreamSubscription>[];

  Jukebox(this.library, this.settings, this.output) : ai = AiDj(settings, library) {
    library.addListener(() => _genreIndex = null);
    settings.addListener(_onSettings);
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

  /// What plays after the current song, if anything is lined up.
  QueueItem? get nextUp =>
      queue.firstOrNull ?? (settings.randomWhenEmpty ? upcoming.firstOrNull : null);

  bool isQueued(Song s) => queue.any((q) => q.song.key == s.key);

  /// Adds a requested track. Starts playback if nothing is playing.
  void request(Song song) => requestAll([song]);

  /// Queues [songs] in order, skipping any already queued or playing.
  /// Returns how many were added.
  int requestAll(Iterable<Song> songs) {
    var added = 0;
    for (final s in songs) {
      if (isQueued(s) || current?.song.key == s.key) continue;
      queue.add(QueueItem(s, library.entryOf(s)));
      added++;
    }
    if (added == 0) return 0;
    // New requests change what the AI should follow; re-pick later.
    if (settings.aiEnabled) _clearUpcoming();
    if (current == null) {
      next();
    } else {
      notifyListeners();
    }
    return added;
  }

  void removeAt(int i) {
    if (!settings.allowDelete || i < 0 || i >= queue.length) return;
    queue.removeAt(i);
    notifyListeners();
  }

  /// Moves a queued song to the front so it plays next.
  void bump(int i) {
    if (!settings.allowBump || i <= 0 || i >= queue.length) return;
    queue.insert(0, queue.removeAt(i));
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

  /// Advances to the next requested track, or a random/AI one.
  Future<void> next() async {
    QueueItem? item;
    if (queue.isNotEmpty) {
      item = queue.removeAt(0);
    } else if (settings.randomWhenEmpty) {
      final recent = _recentKeys();
      // Drop look-ahead picks that have since been played.
      upcoming.removeWhere((u) => recent.contains(u.song.key));
      item = upcoming.isNotEmpty ? upcoming.removeAt(0) : _randomItem();
    }
    current = item;
    progress.value = (Duration.zero, Duration.zero);
    notifyListeners();
    if (item == null) {
      await output.stop();
      return;
    }
    _remember(item);
    _refillIfNeeded();
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

  void _onSettings() {
    // Switching AI or random play on/off invalidates the look-ahead.
    final wantAi = settings.aiEnabled;
    if (upcoming.isNotEmpty && upcoming.first.source != (wantAi ? Source.ai : Source.random)) {
      _clearUpcoming();
      _refillIfNeeded();
    }
  }

  void _clearUpcoming() {
    _refillGen++;
    upcoming.clear();
    aiBusy = false;
  }

  // ------------------------------------------------------- random / AI play

  /// Lines up the next random songs while the current one plays.
  void _refillIfNeeded() {
    if (!settings.randomWhenEmpty || queue.isNotEmpty || upcoming.isNotEmpty || aiBusy) return;
    if (current == null) return;
    final seeds = settings.aiEnabled ? _aiSeeds() : const <Song>[];
    if (seeds.isEmpty) {
      final r = _randomItem();
      if (r != null) upcoming.add(r);
      notifyListeners();
      return;
    }
    final gen = ++_refillGen;
    aiBusy = true;
    aiError = null;
    notifyListeners();
    final exclude = {..._recentKeys(), for (final q in queue) q.song.key, ?current?.song.key};
    ai.pick(seeds, exclude).then((songs) {
      if (gen != _refillGen) return;
      upcoming
        ..clear()
        ..addAll(songs.map((s) => QueueItem(s, library.entryOf(s), source: Source.ai)));
    }).catchError((Object e) {
      if (gen != _refillGen) return;
      debugPrint('AI DJ failed, using random: $e');
      aiError = '$e';
      final r = _randomItem();
      if (r != null) upcoming.add(r);
    }).whenComplete(() {
      if (gen != _refillGen) return;
      aiBusy = false;
      notifyListeners();
    });
  }

  /// Songs that steer the AI: those requested within the look-back window;
  /// if nobody requested anything, whatever played in that window.
  List<Song> _aiSeeds() {
    final since = DateTime.now().subtract(Duration(hours: settings.aiLookbackHours));
    final window = _history.where((h) => h.at.isAfter(since));
    final requested = window.where((h) => !h.random);
    final chosen = (requested.isNotEmpty ? requested : window).take(20);
    return [for (final h in chosen) ?library.songs[h.key]];
  }

  Set<String> _recentKeys() => {for (final h in _history.take(200)) h.key};

  QueueItem? _randomItem() {
    final s = _pickRandom();
    return s == null ? null : QueueItem(s, library.entryOf(s), source: Source.random);
  }

  Song? _pickRandom() {
    final all = library.songs.values.toList(growable: false);
    if (all.isEmpty) return null;
    final recent = _recentKeys();

    // Weight genres from the last 15 plays; tracks people chose count 3x,
    // so random play follows the room rather than drifting on its own.
    final weights = <String, double>{};
    for (final h in _history.take(15)) {
      final s = library.songs[h.key];
      if (s == null) continue;
      final g = library.genresOf(s);
      for (final name in g) {
        weights[name] = (weights[name] ?? 0) + (h.random ? 1 : 3) / g.length;
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
      if (!recent.contains(s.key) && !isQueued(s)) return s;
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
    _history.insert(0, (key: item.song.key, random: item.random, at: DateTime.now()));
    if (_history.length > _historyMax) _history.removeLast();
    SharedPreferences.getInstance().then((p) => p.setStringList('history2', [
          for (final h in _history) '${h.random ? 'r' : 'q'}${h.at.millisecondsSinceEpoch}:${h.key}'
        ]));
  }

  Future<void> _loadHistory() async {
    final p = await SharedPreferences.getInstance();
    for (final h in p.getStringList('history2') ?? const <String>[]) {
      final colon = h.indexOf(':');
      if (colon < 2) continue;
      final ms = int.tryParse(h.substring(1, colon));
      if (ms == null) continue;
      _history.add((
        key: h.substring(colon + 1),
        random: h[0] == 'r',
        at: DateTime.fromMillisecondsSinceEpoch(ms),
      ));
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
