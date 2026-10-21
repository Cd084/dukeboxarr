// ignore_for_file: avoid_print
// Live check of the AI DJ against the cached library and a real Ollama host.
// Skipped unless DUKEBOX_LIVE=1. Run:
//   $env:DUKEBOX_LIVE=1; flutter test test/ai_dj_live_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:dukebox/ai_dj.dart';
import 'package:dukebox/library.dart';
import 'package:dukebox/models.dart';
import 'package:dukebox/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final live = Platform.environment['DUKEBOX_LIVE'] == '1';

  test('AI DJ picks songs following the seeds', () async {
    SharedPreferences.setMockInitialValues({
      'ollamaUrl': Platform.environment['OLLAMA_URL'] ?? 'http://192.168.129.32:11434',
      'aiModel': Platform.environment['AI_MODEL'] ?? 'qwen3.5:9b',
    });
    final settings = await Settings.load();
    final lib = Library(settings);
    final cache = jsonDecode(await File(
            '${Platform.environment['APPDATA']}/ca.dukebox/dukebox/dukebox/library.json')
        .readAsString());
    lib.albums = {for (final a in cache['albums']) a['k']: Album.fromJson(a)};
    lib.songs = {for (final s in cache['songs']) s['k']: Song.fromJson(s)};
    lib.artistGenres = (cache['artistGenres'] as Map)
        .map((k, v) => MapEntry(k as String, (v as List).cast<String>()));

    final seedArtist = Platform.environment['SEED_ARTIST'] ?? 'AC/DC';
    final seeds = lib.songs.values.where((s) => s.artist == seedArtist).take(3).toList();
    expect(seeds, isNotEmpty, reason: 'no songs by $seedArtist');
    print('Seeds: ${seeds.map((s) => '${s.artist} - ${s.title} ${lib.genresOf(s)}').join(' | ')}');

    final sw = Stopwatch()..start();
    final picks = await AiDj(settings, lib).pick(seeds, {});
    print('Picked in ${sw.elapsed.inMilliseconds} ms:');
    for (final s in picks) {
      print('  ${s.artist} - ${s.title} ${lib.genresOf(s)}');
    }
    expect(picks, isNotEmpty);
  }, skip: !live, timeout: const Timeout(Duration(minutes: 4)));
}
