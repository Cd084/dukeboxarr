import 'dart:async';

import 'package:flutter/material.dart';

import '../browse.dart';
import '../models.dart';
import 'actions.dart';
import 'theme.dart';

Future<void> openSearch(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()));

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _q = '';
  late Set<String> _genres;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _genres = {...AppScope.of(context).browse.genres};
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => setState(() => _q = v.trim().toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final entries = app.library.entries;

    final artists = <String, Entry>{};
    final albums = <Entry>[];
    final tracks = <(Song, Entry)>[];
    if (_q.length >= 2) {
      for (final e in entries) {
        if (e.kind != EntryKind.mixedSingles && e.artist.toLowerCase().contains(_q)) {
          artists.putIfAbsent(e.artist, () => e);
        }
        if (e.title.toLowerCase().contains(_q) && e.kind == EntryKind.album) albums.add(e);
        if (tracks.length < 200) {
          for (final s in e.songs) {
            if (s.title.toLowerCase().contains(_q)) tracks.add((s, e));
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Jb.cabinetHi,
        toolbarHeight: 84,
        leading: IconButton(iconSize: 36, icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _onChanged,
          style: const TextStyle(fontSize: 24),
          decoration: const InputDecoration(
            hintText: 'Search artists, albums, songs…',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () {
                  app.browse.setFilter(text: _q, genres: _genres, clearArtist: true);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.filter_alt),
                label: const Text('SHOW ON JUKEBOX'),
              ),
            ),
        ],
      ),
      body: _q.length < 2
          ? _genrePanel(app)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _column('ARTISTS', [
                  for (final MapEntry(key: name, value: e) in artists.entries.take(50))
                    _tile(name, null, Icons.person, () {
                      app.browse.setFilter(artist: name, text: '', genres: {});
                      Navigator.pop(context);
                    }, art: e.thumb),
                ]),
                _column('ALBUMS', [
                  for (final e in albums.take(50))
                    _tile(e.title, '${e.code}  ·  ${e.artist}', Icons.album, () {
                      app.browse.jumpTo(e);
                      Navigator.pop(context);
                    }, art: e.thumb),
                ]),
                _column('SONGS  (tap to queue)', [
                  for (final (s, e) in tracks.take(100))
                    _tile(s.title, '${e.trackCode(e.songs.indexOf(s))}  ·  ${s.artist}', Icons.music_note,
                        () => requestSong(context, s)),
                ], flex: 2),
              ],
            ),
    );
  }

  Widget _genrePanel(AppScope app) {
    // Most common genres first, so the useful ones are at the top.
    final counts = <String, int>{};
    for (final a in app.library.albums.values) {
      for (final g in a.genres) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final genres = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('FILTER BY GENRE',
                style: TextStyle(color: Jb.neon, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3)),
            const Spacer(),
            TextButton(onPressed: () => setState(() => _genres.clear()), child: const Text('Clear')),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () {
                app.browse.setFilter(genres: {..._genres}, text: '', clearArtist: true);
                Navigator.pop(context);
              },
              child: Text(_genres.isEmpty ? 'SHOW ALL' : 'APPLY (${_genres.length})'),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final g in genres)
                    FilterChip(
                      label: Text('$g  ${counts[g]}', style: const TextStyle(fontSize: 18)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      selected: _genres.contains(g),
                      onSelected: (on) => setState(() => on ? _genres.add(g) : _genres.remove(g)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(String title, List<Widget> children, {int flex = 1}) => Expanded(
        flex: flex,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(title,
                  style: const TextStyle(color: Jb.neon, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 3)),
            ),
            Expanded(
              child: children.isEmpty
                  ? const Center(child: Text('No matches', style: TextStyle(color: Jb.chrome)))
                  : ListView(children: children),
            ),
          ],
        ),
      );

  Widget _tile(String title, String? sub, IconData icon, VoidCallback onTap, {String? art}) {
    final url = AppScope.of(context).library.client.artUrl(art, size: 96);
    return ListTile(
      minTileHeight: 64,
      onTap: onTap,
      leading: SizedBox(
        width: 48,
        height: 48,
        child: url == null
            ? Icon(icon, color: Jb.neon, size: 32)
            : ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(url, fit: BoxFit.cover, cacheWidth: 96)),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18)),
      subtitle: sub == null
          ? null
          : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Jb.chrome)),
    );
  }
}
