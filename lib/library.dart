import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'plex_client.dart';
import 'settings.dart';

/// Holds the Plex music library, cached on disk, and the numbered jukebox
/// catalogue built from it.
class Library extends ChangeNotifier {
  final Settings settings;
  Library(this.settings);

  Map<String, Album> albums = {};
  Map<String, Song> songs = {};
  Map<String, List<String>> artistGenres = {};

  List<Entry> entries = [];
  final Map<int, Entry> _byNumber = {};
  final Map<String, Entry> _entryOfSong = {};

  bool loading = false;
  String status = '';
  String? error;
  DateTime? syncedAt;

  PlexClient? _client;
  PlexClient get client => _client ??=
      PlexClient(settings.plexUrl, settings.plexToken, settings.clientId);

  bool get isEmpty => entries.isEmpty;

  Entry? byNumber(int n) => _byNumber[n];
  Entry? entryOf(Song s) => _entryOfSong[s.key];

  List<String> genresOf(Song s) {
    final g = albums[s.albumKey]?.genres ?? const [];
    return g.isNotEmpty ? g : (artistGenres[s.albumArtistKey] ?? const []);
  }

  List<String> get allGenres {
    final set = <String>{for (final a in albums.values) ...a.genres};
    return set.toList()..sort();
  }

  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}dukebox');
    await d.create(recursive: true);
    return d;
  }

  void resetClient() => _client = null;

  /// Loads from the disk cache if present, otherwise syncs from Plex.
  Future<void> init() async {
    final f = File('${(await _dir()).path}/library.json');
    if (await f.exists()) {
      _set(loading: true, status: 'Loading library…');
      try {
        final data = await compute(_decodeCache, await f.readAsString());
        albums = data.albums;
        songs = data.songs;
        artistGenres = data.artistGenres;
        syncedAt = (await f.lastModified());
        await rebuildCatalog();
        _set(loading: false, status: '');
        return;
      } catch (e) {
        debugPrint('cache unreadable, resyncing: $e');
      }
    }
    await sync();
  }

  Future<void> sync() async {
    error = null;
    _set(loading: true, status: 'Connecting to Plex…');
    try {
      final sections = await client.musicSections();
      final section = sections[settings.musicLibrary] ??
          (sections.isNotEmpty ? sections.values.first : null);
      if (section == null) throw PlexException('No music library found on this server');

      _set(status: 'Reading artists…');
      final rawArtists = await client.all(section, 8);
      _set(status: 'Reading albums…');
      final rawAlbums = await client.all(section, 9);
      final rawTracks = await client.all(section, 10,
          progress: (d, t) => _set(status: 'Reading tracks… $d / $t'));

      _set(status: 'Building catalogue…');
      final data = await compute(_parsePlex, (rawArtists, rawAlbums, rawTracks));
      albums = data.albums;
      songs = data.songs;
      artistGenres = data.artistGenres;
      syncedAt = DateTime.now();
      final json = await compute(_encodeCache, data);
      await File('${(await _dir()).path}/library.json').writeAsString(json);
      await rebuildCatalog();
    } catch (e) {
      error = e.toString();
    }
    _set(loading: false, status: '');
  }

  /// Groups songs into numbered entries. Numbers persist across syncs.
  Future<void> rebuildCatalog({bool renumber = false}) async {
    final built = _buildEntries();
    final numFile = File('${(await _dir()).path}/numbers.json');
    final saved = <String, int>{};
    if (!renumber && await numFile.exists()) {
      saved.addAll((jsonDecode(await numFile.readAsString()) as Map).cast<String, int>());
    }
    final live = {for (final e in built) e.id};
    saved.removeWhere((id, _) => !live.contains(id));
    final used = saved.values.toSet();
    var next = 1;
    int nextFree() {
      while (used.contains(next)) {
        next++;
      }
      used.add(next);
      return next;
    }

    for (final e in built) {
      e.number = saved[e.id] ??= nextFree();
    }
    await numFile.writeAsString(jsonEncode(saved));

    entries = built;
    _byNumber
      ..clear()
      ..addEntries(built.map((e) => MapEntry(e.number, e)));
    _entryOfSong.clear();
    for (final e in built) {
      for (final s in e.songs) {
        _entryOfSong[s.key] = e;
      }
    }
    notifyListeners();
  }

  List<Entry> _buildEntries() {
    final byAlbum = <String, List<Song>>{};
    for (final s in songs.values) {
      (byAlbum[s.albumKey] ??= []).add(s);
    }
    for (final l in byAlbum.values) {
      l.sort((a, b) => a.disc != b.disc
          ? a.disc - b.disc
          : a.index != b.index
              ? a.index - b.index
              : a.title.compareTo(b.title));
    }

    final out = <Entry>[];
    final loose = <String, List<Song>>{}; // album artist -> loose songs
    final looseSort = <String, String>{};

    for (final MapEntry(key: ak, value: list) in byAlbum.entries) {
      final al = albums[ak];
      if (al == null) continue;
      if (list.length >= settings.albumMinTracks) {
        final chunks = _chunk(list, 99);
        for (var i = 0; i < chunks.length; i++) {
          out.add(Entry(
            id: i == 0 ? 'a:$ak' : 'a:$ak:${i + 1}',
            kind: EntryKind.album,
            title: chunks.length > 1 ? '${al.title} (Part ${i + 1})' : al.title,
            artist: al.artist,
            sortKey: '${al.artistSort}\u0001${al.year ?? 0}\u0001${al.title.toLowerCase()}',
            thumb: al.thumb,
            year: al.year,
            songs: chunks[i],
          ));
        }
      } else {
        (loose[al.artistKey] ??= []).addAll(list);
        looseSort[al.artistKey] = al.artistSort;
      }
    }

    final mixed = <Song>[];
    for (final MapEntry(key: artistKey, value: list) in loose.entries) {
      list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      if (list.length >= settings.artistSinglesMin) {
        final chunks = _chunk(list, 99);
        final name = albums[list.first.albumKey]?.artist ?? list.first.artist;
        for (var i = 0; i < chunks.length; i++) {
          out.add(Entry(
            id: i == 0 ? 's:$artistKey' : 's:$artistKey:${i + 1}',
            kind: EntryKind.artistSingles,
            title: chunks.length > 1 ? 'Singles & EPs (Part ${i + 1})' : 'Singles & EPs',
            artist: name,
            sortKey: '${looseSort[artistKey]}\u0002',
            thumb: albums[chunks[i].first.albumKey]?.thumb,
            songs: chunks[i],
          ));
        }
      } else {
        mixed.addAll(list);
      }
    }

    String sortOf(Song s) => albums[s.albumKey]?.artistSort ?? s.artist.toLowerCase();
    mixed.sort((a, b) => sortOf(a).compareTo(sortOf(b)));
    for (final chunk in _chunk(mixed, settings.mixedSinglesSize)) {
      String initial(Song s) {
        final c = sortOf(s).isEmpty ? '#' : sortOf(s)[0].toUpperCase();
        return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
      }
      final a = initial(chunk.first), b = initial(chunk.last);
      out.add(Entry(
        id: 'm:${chunk.first.key}',
        kind: EntryKind.mixedSingles,
        title: a == b ? 'Singles · $a' : 'Singles · $a–$b',
        artist: 'Various Artists',
        sortKey: '${sortOf(chunk.first)}\u0003',
        songs: chunk,
      ));
    }

    out.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return out;
  }

  static List<List<T>> _chunk<T>(List<T> l, int n) =>
      [for (var i = 0; i < l.length; i += n) l.sublist(i, i + n > l.length ? l.length : i + n)];

  void _set({bool? loading, String? status}) {
    if (loading != null) this.loading = loading;
    if (status != null) this.status = status;
    notifyListeners();
  }
}

// ---------------------------------------------------------------- isolates

typedef _LibData = ({
  Map<String, Album> albums,
  Map<String, Song> songs,
  Map<String, List<String>> artistGenres,
});

String _sortName(String s) {
  final l = s.toLowerCase().trim();
  return l.startsWith('the ') ? l.substring(4) : l;
}

List<String> _genres(Map m) =>
    [for (final g in (m['Genre'] as List? ?? const [])) g['tag'] as String];

_LibData _parsePlex(
    (List<Map<String, dynamic>>, List<Map<String, dynamic>>, List<Map<String, dynamic>>) raw) {
  final (rawArtists, rawAlbums, rawTracks) = raw;
  final artistSort = <String, String>{};
  final artistGenres = <String, List<String>>{};
  for (final a in rawArtists) {
    final k = a['ratingKey'].toString();
    artistSort[k] = _sortName((a['titleSort'] ?? a['title'] ?? '') as String);
    final g = _genres(a);
    if (g.isNotEmpty) artistGenres[k] = g;
  }
  final albums = <String, Album>{};
  for (final a in rawAlbums) {
    final k = a['ratingKey'].toString();
    final ak = a['parentRatingKey']?.toString() ?? '';
    final artist = (a['parentTitle'] ?? 'Unknown Artist') as String;
    albums[k] = Album(
      key: k,
      title: (a['title'] ?? '') as String,
      artist: artist,
      artistKey: ak,
      artistSort: artistSort[ak] ?? _sortName(artist),
      year: a['year'] as int?,
      thumb: a['thumb'] as String?,
      genres: _genres(a),
    );
  }
  final songs = <String, Song>{};
  for (final t in rawTracks) {
    final parts = ((t['Media'] as List?)?.firstOrNull?['Part'] as List?);
    final partKey = parts?.firstOrNull?['key'] as String?;
    if (partKey == null) continue;
    final k = t['ratingKey'].toString();
    songs[k] = Song(
      key: k,
      title: (t['title'] ?? '') as String,
      artist: (t['originalTitle'] ?? t['grandparentTitle'] ?? '') as String,
      albumKey: t['parentRatingKey']?.toString() ?? '',
      albumArtistKey: t['grandparentRatingKey']?.toString() ?? '',
      disc: (t['parentIndex'] as int?) ?? 1,
      index: (t['index'] as int?) ?? 0,
      durationMs: (t['duration'] as int?) ?? 0,
      partKey: partKey,
    );
  }
  return (albums: albums, songs: songs, artistGenres: artistGenres);
}

String _encodeCache(_LibData d) => jsonEncode({
      'albums': [for (final a in d.albums.values) a.toJson()],
      'songs': [for (final s in d.songs.values) s.toJson()],
      'artistGenres': d.artistGenres,
    });

_LibData _decodeCache(String s) {
  final j = jsonDecode(s) as Map<String, dynamic>;
  return (
    albums: {
      for (final a in (j['albums'] as List)) a['k'] as String: Album.fromJson(a)
    },
    songs: {for (final t in (j['songs'] as List)) t['k'] as String: Song.fromJson(t)},
    artistGenres: (j['artistGenres'] as Map)
        .map((k, v) => MapEntry(k as String, (v as List).cast<String>())),
  );
}
