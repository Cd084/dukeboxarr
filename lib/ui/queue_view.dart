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
            child: jb.queue.isEmpty
                ? Center(
                    child: Text(
                        app.settings.randomWhenEmpty
                            ? 'Queue is empty — random play will pick the next song'
                            : 'Queue is empty',
                        style: const TextStyle(color: Jb.chrome, fontSize: 18)))
                : ListView.builder(
                    itemCount: jb.queue.length,
                    itemBuilder: (context, i) => _row(context, jb.queue[i], index: i),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, QueueItem q, {int? index, bool nowPlaying = false}) {
    final app = AppScope.of(context);
    final code = q.entry?.trackCode(q.entry!.songs.indexOf(q.song)) ?? '';
    return ListTile(
      minTileHeight: 64,
      leading: SizedBox(
        width: 90,
        child: Text(nowPlaying ? '▶ NOW' : '${index! + 1}.',
            style: const TextStyle(color: Jb.neon, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      title: Text(q.song.title, style: const TextStyle(fontSize: 20, color: Colors.white)),
      subtitle: Text('$code   ${q.song.artist}${q.random ? '   · random' : ''}',
          style: const TextStyle(color: Jb.chrome)),
      trailing: !nowPlaying && app.settings.allowDelete
          ? IconButton(
              iconSize: 32,
              color: Colors.redAccent,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => app.jukebox.removeAt(index!),
            )
          : null,
    );
  }
}
