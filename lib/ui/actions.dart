import 'package:flutter/material.dart';

import '../browse.dart';
import '../models.dart';

/// Queues [song] (no duplicates) and confirms with a snackbar.
void requestSong(BuildContext context, Song song) {
  final app = AppScope.of(context);
  final jb = app.jukebox;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  String msg;
  if (jb.current?.song.key == song.key) {
    msg = '“${song.title}” is playing now';
  } else if (jb.isQueued(song)) {
    msg = '“${song.title}” is already in the queue';
  } else {
    final wasIdle = jb.idle;
    jb.request(song);
    msg = wasIdle
        ? 'Now playing “${song.title}”'
        : jb.current?.random == true && jb.queue.length == 1
            ? '“${song.title}” plays next'
            : '“${song.title}” added — #${jb.queue.length} in queue';
  }
  messenger.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}
