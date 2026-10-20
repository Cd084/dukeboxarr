import 'package:flutter/material.dart';

import '../browse.dart';
import '../models.dart';
import 'theme.dart';

const kCardHeaderHeight = 104.0;
const kTrackRowHeight = 38.0;

/// How many track rows fit in a card of [height].
int trackCapacity(double height) =>
    ((height - kCardHeaderHeight - 12) / kTrackRowHeight).floor().clamp(3, 99);

/// A jukebox title strip: number band, cover + album info, and track rows.
class AlbumCard extends StatelessWidget {
  final CardPart part;
  final void Function(Song song) onTrackTap;

  const AlbumCard({super.key, required this.part, required this.onTrackTap});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final e = part.entry;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Jb.paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Jb.chrome, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: kCardHeaderHeight, child: _header(app, e)),
          Expanded(
            child: ListenableBuilder(
              listenable: app.jukebox,
              builder: (context, _) => Column(
                children: [
                  for (var i = part.start; i < part.end; i++)
                    _TrackRow(
                      number: i + 1,
                      song: e.songs[i],
                      showArtist: e.kind != EntryKind.album || e.songs[i].artist != e.artist,
                      nowPlaying: app.jukebox.current?.song.key == e.songs[i].key,
                      queued: app.jukebox.isQueued(e.songs[i]),
                      onTap: () => onTrackTap(e.songs[i]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppScope app, Entry e) {
    final art = app.library.client.artUrl(e.thumb, size: 160);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Jb.band,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            children: [
              Text(e.code,
                  style: const TextStyle(
                      fontFamilyFallback: Jb.mono,
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3)),
              const Spacer(),
              if (part.parts > 1)
                Text('${part.part} / ${part.parts}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: art == null
                        ? Container(
                            color: Jb.ink,
                            child: const Icon(Icons.album, color: Jb.neon, size: 40))
                        : Image.network(art,
                            fit: BoxFit.cover,
                            cacheWidth: 160,
                            errorBuilder: (_, _, _) => Container(
                                color: Jb.ink,
                                child: const Icon(Icons.album, color: Jb.neon, size: 40))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(e.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Jb.ink, fontSize: 17, fontWeight: FontWeight.w800, height: 1.1)),
                      const SizedBox(height: 2),
                      Text(
                          [e.artist.toUpperCase(), if (e.year != null) '${e.year}'].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Jb.band, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 2, color: Jb.band),
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  final int number;
  final Song song;
  final bool showArtist;
  final bool nowPlaying;
  final bool queued;
  final VoidCallback onTap;

  const _TrackRow({
    required this.number,
    required this.song,
    required this.showArtist,
    required this.nowPlaying,
    required this.queued,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: nowPlaying ? Jb.playing : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Jb.neonDim,
        child: Container(
          height: kTrackRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Jb.paperLine))),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(number.toString().padLeft(2, '0'),
                    style: const TextStyle(
                        fontFamilyFallback: Jb.mono,
                        color: Jb.band,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: song.title),
                    if (showArtist)
                      TextSpan(
                          text: '  ${song.artist}',
                          style: const TextStyle(color: Jb.inkSoft, fontSize: 12, fontWeight: FontWeight.normal)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Jb.ink, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              if (nowPlaying)
                const Icon(Icons.graphic_eq, color: Jb.band, size: 20)
              else if (queued)
                const Icon(Icons.queue_music, color: Jb.inkSoft, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
