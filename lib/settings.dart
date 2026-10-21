import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends ChangeNotifier {
  final SharedPreferences _p;
  Settings._(this._p);

  static Future<Settings> load() async {
    final p = await SharedPreferences.getInstance();
    if (p.getString('clientId') == null) {
      final r = Random.secure();
      await p.setString('clientId',
          List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join());
    }
    return Settings._(p);
  }

  String get clientId => _p.getString('clientId')!;

  String get plexUrl => _p.getString('plexUrl') ?? '';
  String get plexToken => _p.getString('plexToken') ?? '';
  String get musicLibrary => _p.getString('musicLibrary') ?? 'Music';
  bool get isConfigured => plexUrl.isNotEmpty && plexToken.isNotEmpty;

  /// Queue control: may guests remove queued tracks / skip the current one?
  bool get allowDelete => _p.getBool('allowDelete') ?? true;
  bool get allowSkip => _p.getBool('allowSkip') ?? true;

  /// Play genre-matched random tracks when the queue runs dry.
  bool get randomWhenEmpty => _p.getBool('randomWhenEmpty') ?? true;

  /// Artists with at least this many loose singles get their own card;
  /// the rest are packed into shared "Singles" cards.
  int get artistSinglesMin => _p.getInt('artistSinglesMin') ?? 3;

  /// Tracks per shared "Singles" selection number.
  int get mixedSinglesSize => _p.getInt('mixedSinglesSize') ?? 20;

  /// Releases with fewer tracks than this count as singles/EPs.
  int get albumMinTracks => _p.getInt('albumMinTracks') ?? 4;

  int get cardsPerPage => _p.getInt('cardsPerPage') ?? 4;

  /// May guests move a queued song to the top?
  bool get allowBump => _p.getBool('allowBump') ?? true;

  /// Re-sync the library when the cache is older than this; 0 = never.
  int get autoSyncHours => _p.getInt('autoSyncHours') ?? 24;

  // ---- AI random play (Ollama) ----
  bool get aiEnabled => _p.getBool('aiEnabled') ?? false;
  String get ollamaUrl => _p.getString('ollamaUrl') ?? 'http://localhost:11434';
  String get aiModel => _p.getString('aiModel') ?? '';

  /// Songs requested within this many hours steer the AI's picks.
  int get aiLookbackHours => _p.getInt('aiLookbackHours') ?? 3;

  Future<void> _set(String k, Object v) async {
    switch (v) {
      case bool b: await _p.setBool(k, b);
      case int i: await _p.setInt(k, i);
      case String s: await _p.setString(k, s);
    }
    notifyListeners();
  }

  Future<void> setPlex(String url, String token, String library) async {
    await _p.setString('plexUrl', url.trim());
    await _p.setString('plexToken', token.trim());
    await _set('musicLibrary', library.trim());
  }

  set allowDelete(bool v) => _set('allowDelete', v);
  set allowSkip(bool v) => _set('allowSkip', v);
  set randomWhenEmpty(bool v) => _set('randomWhenEmpty', v);
  set artistSinglesMin(int v) => _set('artistSinglesMin', v);
  set mixedSinglesSize(int v) => _set('mixedSinglesSize', v);
  set albumMinTracks(int v) => _set('albumMinTracks', v);
  set cardsPerPage(int v) => _set('cardsPerPage', v);
  /// Settings lock; empty = unlocked.
  String get adminPin => _p.getString('adminPin') ?? '';
  set adminPin(String v) => _set('adminPin', v);

  /// Show a 0–9 keypad strip under the A–Z bar.
  bool get showInlineKeypad => _p.getBool('showInlineKeypad') ?? false;
  set showInlineKeypad(bool v) => _set('showInlineKeypad', v);

  /// Output: empty id = this device, otherwise a Plex player.
  String get outputId => _p.getString('outputId') ?? '';
  String get outputName => _p.getString('outputName') ?? '';
  List<String> get outputUris => _p.getStringList('outputUris') ?? const [];
  Future<void> setOutput(String id, String name, List<String> uris) async {
    await _p.setString('outputName', name);
    await _p.setStringList('outputUris', uris);
    await _set('outputId', id);
  }

  String get serverId => _p.getString('serverId') ?? '';
  set serverId(String v) => _p.setString('serverId', v);

  set allowBump(bool v) => _set('allowBump', v);
  set autoSyncHours(int v) => _set('autoSyncHours', v);
  set aiEnabled(bool v) => _set('aiEnabled', v);
  set ollamaUrl(String v) => _set('ollamaUrl', v.trim().replaceAll(RegExp(r'/+$'), ''));
  set aiModel(String v) => _set('aiModel', v);
  set aiLookbackHours(int v) => _set('aiLookbackHours', v);
}
