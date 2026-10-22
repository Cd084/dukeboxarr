import 'package:flutter/material.dart';

import '../browse.dart';
import '../models.dart';
import '../plex_client.dart';
import 'theme.dart';

Future<void> openPlaylists(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaylistsScreen()));

/// One user's playlists, read with that user's own server access.
class _Group {
  final String title;
  final PlexClient client;
  final List<Map<String, dynamic>> lists;
  const _Group(this.title, this.client, this.lists);
}

/// Plex audio playlists — the current user's, then other Plex Home users'
/// (unless turned off in Settings). Picking one queues its songs.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});
  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  static const _maxWhole = 200;
  late Future<List<_Group>> _groups;
  String? _loading; // ratingKey of the playlist being fetched

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _groups = _load(AppScope.of(context));
  }

  static List<Map<String, dynamic>> _nonEmpty(List<Map<String, dynamic>> l) =>
      l.where((p) => ((p['leafCount'] as int?) ?? 0) > 0).toList();

  Future<List<_Group>> _load(AppScope app) async {
    final s = app.settings;
    final client = app.library.client;
    final groups = [
      _Group(s.plexUserTitle.isEmpty ? 'Your playlists' : '${s.plexUserTitle}\'s playlists', client,
          _nonEmpty(await client.playlists())),
    ];
    if (!s.showSharedPlaylists) return groups;

    // Other Plex Home users. The account owner's playlists are readable with
    // the sign-in token; other users need switching to, which is skipped for
    // PIN-protected ones (it would ask for their PIN every time).
    try {
      var serverId = s.serverId;
      if (serverId.isEmpty) serverId = s.serverId = await client.machineId() ?? '';
      final users = await PlexClient.homeUsers(s.clientId, s.plexAccountToken);
      for (final u in users) {
        final isCurrent = u.uuid == s.plexUserUuid || (u.admin && s.plexUserUuid.isEmpty);
        if (isCurrent || (u.protected && !u.admin)) continue;
        try {
          final token = u.admin
              ? s.plexAccountToken
              : await PlexClient.switchHomeUser(s.clientId, s.plexAccountToken, u.uuid, serverId);
          final other = client.withToken(token);
          final lists = _nonEmpty(await other.playlists());
          if (lists.isNotEmpty) groups.add(_Group('${u.title}\'s playlists', other, lists));
        } catch (e) {
          debugPrint('playlists for ${u.title} unavailable: $e');
        }
      }
    } catch (e) {
      debugPrint('Plex Home users unavailable: $e'); // e.g. signed in with a server-only token
    }
    return groups;
  }

  Future<void> _choose(_Group g, Map<String, dynamic> pl) async {
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _loading = pl['ratingKey'].toString());
    List<Song> songs;
    try {
      final keys = await g.client.playlistItemKeys(pl['ratingKey'].toString());
      // Only songs the current user's library has (restricted users see less).
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Jb.cabinetHi,
        toolbarHeight: 72,
        leading: IconButton(iconSize: 36, icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: const Text('PLAYLISTS',
            style: TextStyle(color: Jb.neon, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 4)),
      ),
      body: FutureBuilder(
        future: _groups,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('Could not load playlists: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Jb.neon));
          final groups = snap.data!.where((g) => g.lists.isNotEmpty).toList();
          if (groups.isEmpty) {
            return const Center(child: Text('No music playlists on this server', style: TextStyle(fontSize: 20)));
          }
          return CustomScrollView(
            slivers: [
              for (final g in groups) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(g.title.toUpperCase(),
                        style: const TextStyle(
                            color: Jb.neon, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 3)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid.extent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.78,
                    children: [for (final pl in g.lists) _tile(g, pl)],
                  ),
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(_Group g, Map<String, dynamic> pl) => InkWell(
        onTap: () => _choose(g, pl),
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
                  _art(g, pl),
                  if (_loading == pl['ratingKey'].toString())
                    const ColoredBox(
                        color: Colors.black54, child: Center(child: CircularProgressIndicator(color: Jb.neon))),
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
      );

  /// Cover art is fetched as the playlist's owner, who can see it.
  Widget _art(_Group g, Map<String, dynamic> pl) {
    final url = g.client.artUrl((pl['composite'] ?? pl['thumb']) as String?, size: 300);
    const fallback = ColoredBox(color: Jb.ink, child: Icon(Icons.queue_music, color: Jb.neon, size: 64));
    return url == null
        ? fallback
        : Image.network(url, fit: BoxFit.cover, cacheWidth: 300, errorBuilder: (_, _, _) => fallback);
  }
}
