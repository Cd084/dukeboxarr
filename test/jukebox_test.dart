import 'dart:async';

import 'package:dukebox/jukebox.dart';
import 'package:dukebox/library.dart';
import 'package:dukebox/models.dart';
import 'package:dukebox/output.dart';
import 'package:dukebox/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeOutput implements AudioOutput {
  final played = <String>[];
  final _done = StreamController<bool>.broadcast();
  void finish() => _done.add(true);

  @override
  Stream<bool> get completed => _done.stream;
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Future<void> play(String url) async => played.add(url);
  @override
  Future<void> togglePause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setVolume(double percent) async {}
  @override
  Future<void> dispose() async {}
}

Song song(String k) => Song(
    key: k, title: 'T$k', artist: 'A', albumKey: 'al', albumArtistKey: 'ar',
    disc: 1, index: int.parse(k), durationMs: 1000, partKey: '/p/$k');

void main() {
  late Jukebox jb;
  late FakeOutput out;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'plexUrl': 'http://x', 'plexToken': 't'});
    final settings = await Settings.load();
    final lib = Library(settings)
      ..songs = {for (var i = 1; i <= 40; i++) '$i': song('$i')};
    out = FakeOutput();
    jb = Jukebox(lib, settings, out);
  });

  test('first request plays at once; later ones queue; duplicates skipped', () async {
    jb.request(song('1'));
    await pumpEventQueue();
    expect(jb.current?.song.key, '1');
    expect(jb.requestAll([song('2'), song('3'), song('2'), song('1')]), 2);
    expect(jb.queue.map((q) => q.song.key), ['2', '3']);
    expect(jb.nextUp?.song.key, '2');
  });

  test('bump moves a song to the front', () async {
    jb.request(song('1'));
    jb.requestAll([song('2'), song('3'), song('4')]);
    jb.bump(2);
    expect(jb.queue.map((q) => q.song.key), ['4', '2', '3']);
    jb.settings.allowBump = false;
    jb.bump(2);
    expect(jb.queue.map((q) => q.song.key), ['4', '2', '3']);
  });

  test('request waits for the current random song, then plays next', () async {
    await jb.togglePause(); // nothing queued: starts random play
    expect(jb.current?.source, Source.random);
    expect(jb.nextUp?.source, Source.random, reason: 'a random pick is lined up');
    jb.request(song('5'));
    expect(jb.current?.source, Source.random, reason: 'current song is not interrupted');
    expect(jb.nextUp?.song.key, '5');
    out.finish();
    await pumpEventQueue();
    expect(jb.current?.song.key, '5');
  });
}
