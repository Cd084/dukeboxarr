import 'package:flutter/material.dart';

import '../browse.dart';
import 'queue_view.dart';
import 'theme.dart';

String fmtDuration(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final jb = app.jukebox;
    return ListenableBuilder(
      listenable: Listenable.merge([jb, app.settings]),
      builder: (context, _) {
        final cur = jb.current;
        final album = cur == null ? null : app.library.albums[cur.song.albumKey];
        final art = app.library.client.artUrl(album?.thumb, size: 160);
        return Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF3A1F17), Jb.cabinet, Color(0xFF3A1F17)]),
            border: Border(bottom: BorderSide(color: Jb.neon, width: 2)),
          ),
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: art == null
                      ? Container(color: Jb.cabinetHi, child: const Icon(Icons.album, color: Jb.neon, size: 44))
                      : Image.network(art, fit: BoxFit.cover, cacheWidth: 160),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: cur == null
                    ? Text(
                        app.settings.randomWhenEmpty
                            ? 'Make a selection — or press play for random'
                            : 'Make a selection',
                        style: const TextStyle(color: Jb.neon, fontSize: 22, fontWeight: FontWeight.w600))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(children: [
                            if (cur.entry != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Text(cur.entry!.trackCode(cur.entry!.songs.indexOf(cur.song)),
                                    style: const TextStyle(
                                        fontFamilyFallback: Jb.mono, color: Jb.neon, fontSize: 16, letterSpacing: 2)),
                              ),
                            if (cur.random)
                              const Text('RANDOM',
                                  style: TextStyle(color: Jb.chrome, fontSize: 12, letterSpacing: 2)),
                          ]),
                          Text(cur.song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                          Text([cur.song.artist, if (album != null) album.title].join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Jb.chrome, fontSize: 14)),
                        ],
                      ),
              ),
              SizedBox(
                width: 220,
                child: ValueListenableBuilder(
                  valueListenable: jb.progress,
                  builder: (context, p, _) {
                    final (pos, dur) = p;
                    final frac = dur.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LinearProgressIndicator(
                          value: frac.clamp(0, 1),
                          minHeight: 6,
                          color: Jb.neon,
                          backgroundColor: Jb.cabinetHi,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(fmtDuration(pos), style: const TextStyle(color: Jb.chrome)),
                            Text(fmtDuration(dur), style: const TextStyle(color: Jb.chrome)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              _RoundButton(
                icon: jb.playing ? Icons.pause : Icons.play_arrow,
                onTap: jb.togglePause,
              ),
              if (app.settings.allowSkip) ...[
                const SizedBox(width: 8),
                _RoundButton(icon: Icons.skip_next, onTap: cur == null ? null : jb.skip),
              ],
              const SizedBox(width: 8),
              _QueueButton(count: jb.queue.length),
            ],
          ),
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: Jb.chromeButton().gradient,
            border: Jb.chromeButton().border,
          ),
          child: Icon(icon, size: 36, color: onTap == null ? Colors.white24 : Jb.neon),
        ),
      );
}

class _QueueButton extends StatelessWidget {
  final int count;
  const _QueueButton({required this.count});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => showQueue(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: Jb.chromeButton(active: count > 0),
          child: Row(children: [
            Icon(Icons.queue_music, size: 30, color: count > 0 ? Jb.ink : Jb.neon),
            const SizedBox(width: 8),
            Text('$count',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: count > 0 ? Jb.ink : Jb.neon)),
          ]),
        ),
      );
}
