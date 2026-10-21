import 'package:flutter/material.dart';

import '../browse.dart';
import '../models.dart';
import 'theme.dart';

Future<void> openPlaylists(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaylistsScreen()));

/// Plex audio playlists; picking one queues all of its songs.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});
  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  static const _maxWhole = 200;
  late Future<List<Map<String, dynamic>>> _lists;
  String? _loading; // ratingKey of the playlist being fetched

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lists = AppScope.of(context).library.client.playlists().then(
        (l) => l.where((p) => ((p['leafCount'] as int?) ?? 0) > 0).toList());
  }

  Future<void> _choose(Map<String, dynamic> pl) async {
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _loading = pl['ratingKey'].toString());
    List<Song> songs;
    try {
      final keys = await app.library.client.playlistItemKeys(pl['ratingKey'].toString());
      songs = [for (final k in keys) ?app.library.songs[k]];
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not load playlist: $e')));
      return;
    } finally {
      if (mounted) setState(() => _loading = null);
    }
    if (!mounted) return;
    if (songs.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('“${pl['title']}” has no songs from this library')));
      return;
    }
    // Big (often smart) playlists like "All Music" would swamp the queue:
    // offer a random sample instead of everything.
    final big = songs.length > _maxWhole;
    Widget sample(int n) => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
          onPressed: () => Navigator.pop(context, 'r$n'),
          icon: const Icon(Icons.shuffle),
          label: Text('RANDOM $n'),
        );
    final mode = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Jb.cabinetHi,
        title: Text(pl['title'] as String, style: const TextStyle(color: Jb.neon)),
        content: Text(
            big
                ? 'This playlist has ${songs.length} songs. Queue a random selection?'
                : 'Add ${songs.length} songs to the queue?',
            style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (big) ...[
            sample(25),
            sample(50),
            sample(100),
          ] else ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: () => Navigator.pop(context, 'shuffle'),
              icon: const Icon(Icons.shuffle),
              label: const Text('SHUFFLE'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'inorder'),
              icon: const Icon(Icons.playlist_add),
              label: const Text('IN ORDER'),
            ),
          ],
        ],
      ),
    );
    if (mode == null) return;
    if (mode != 'inorder') songs.shuffle();
    if (mode.startsWith('r')) songs = songs.take(int.parse(mode.substring(1))).toList();
    final added = app.jukebox.requestAll(songs);
    messenger.showSnackBar(SnackBar(
      content: Text(added == songs.length
          ? 'Queued ${songs.length} songs from “${pl['title']}”'
          : 'Queued $added songs from “${pl['title']}” (${songs.length - added} already queued)'),
    ));
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Jb.cabinetHi,
        toolbarHeight: 72,
        leading: IconButton(iconSize: 36, icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: const Text('PLAYLISTS',
            style: TextStyle(color: Jb.neon, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 4)),
      ),
      body: FutureBuilder(
        future: _lists,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Could not load playlists: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Jb.neon));
          final lists = snap.data!;
          if (lists.isEmpty) {
            return const Center(child: Text('No music playlists on this server', style: TextStyle(fontSize: 20)));
          }
          return GridView.extent(
            padding: const EdgeInsets.all(20),
            maxCrossAxisExtent: 240,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.78,
            children: [
              for (final pl in lists)
                InkWell(
                  onTap: () => _choose(pl),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Jb.paper,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Jb.chrome, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Stack(fit: StackFit.expand, children: [
                            _art(app, pl),
                            if (_loading == pl['ratingKey'].toString())
                              const ColoredBox(
                                  color: Colors.black54,
                                  child: Center(child: CircularProgressIndicator(color: Jb.neon))),
                          ]),
                        ),
                        Container(
                          color: Jb.band,
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pl['title'] as String? ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                              Text('${pl['leafCount'] ?? 0} songs${pl['smart'] == true ? ' · smart' : ''}',
                                  style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _art(AppScope app, Map<String, dynamic> pl) {
    final url = app.library.client.artUrl((pl['composite'] ?? pl['thumb']) as String?, size: 300);
    const fallback = ColoredBox(color: Jb.ink, child: Icon(Icons.queue_music, color: Jb.neon, size: 64));
    return url == null
        ? fallback
        : Image.network(url, fit: BoxFit.cover, cacheWidth: 300, errorBuilder: (_, _, _) => fallback);
  }
}

