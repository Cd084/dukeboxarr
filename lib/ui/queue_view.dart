import 'package:flutter/material.dart';

import '../browse.dart';
import '../models.dart';
import 'theme.dart';

void showQueue(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Jb.cabinetHi,
      constraints: const BoxConstraints(maxWidth: 900),
      builder: (_) => FractionallySizedBox(heightFactor: 0.8, child: const QueueView()),
    );

class QueueView extends StatelessWidget {
  const QueueView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final jb = app.jukebox;
    return ListenableBuilder(
      listenable: jb,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
            child: Row(children: [
              const Text('UP NEXT',
                  style: TextStyle(color: Jb.neon, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4)),
              const Spacer(),
              IconButton(
                  iconSize: 36, onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          if (jb.current != null) _row(context, jb.current!, nowPlaying: true),
          const Divider(color: Jb.neonDim),
          Expanded(
            child: ListView(
              children: [
                if (jb.queue.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        app.settings.randomWhenEmpty
                            ? 'Queue is empty — ${app.settings.aiEnabled ? 'the AI DJ' : 'random play'} picks the next song'
                            : 'Queue is empty',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Jb.chrome, fontSize: 18)),
                  ),
                for (var i = 0; i < jb.queue.length; i++) _row(context, jb.queue[i], index: i),
                if (app.settings.randomWhenEmpty && (jb.upcoming.isNotEmpty || jb.aiBusy)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                    child: Text(
                        jb.aiBusy
                            ? 'AI DJ IS CHOOSING…'
                            : jb.upcoming.first.source == Source.ai
                                ? 'THEN — AI DJ PICKS'
                                : 'THEN — RANDOM',
                        style: const TextStyle(color: Jb.neonDim, fontSize: 16, letterSpacing: 3)),
                  ),
                  for (final u in jb.upcoming) Opacity(opacity: 0.6, child: _row(context, u, upcoming: true)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, QueueItem q, {int? index, bool nowPlaying = false, bool upcoming = false}) {
    final app = AppScope.of(context);
    final code = q.entry?.trackCode(q.entry!.songs.indexOf(q.song)) ?? '';
    final tag = switch (q.source) { Source.ai => '   · AI pick', Source.random => '   · random', _ => '' };
    final canBump = index != null && index > 0 && app.settings.allowBump;
    final canDelete = index != null && app.settings.allowDelete;
    return ListTile(
      minTileHeight: 64,
      leading: SizedBox(
        width: 90,
        child: Text(nowPlaying ? '▶ NOW' : upcoming ? '' : '${index! + 1}.',
            style: const TextStyle(color: Jb.neon, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      title: Text(q.song.title, style: const TextStyle(fontSize: 20, color: Colors.white)),
      subtitle: Text('$code   ${q.song.artist}$tag', style: const TextStyle(color: Jb.chrome)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (canBump)
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 52), foregroundColor: Jb.neon),
            icon: const Icon(Icons.vertical_align_top, size: 28),
            label: const Text('BUMP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: () => app.jukebox.bump(index),
          ),
        if (canDelete)
          IconButton(
            iconSize: 32,
            color: Colors.redAccent,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => app.jukebox.removeAt(index),
          ),
      ]),
    );
  }
}
