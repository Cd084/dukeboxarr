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

  /// The token you signed in with (your Plex account). Kept so you can switch
  /// between Plex Home users without signing in again. Older installs only
  /// had plexToken, which was the account token.
  String get plexAccountToken => _p.getString('plexAccountToken') ?? plexToken;

  /// The Plex Home user DukeBoxarr acts as; empty = the signed-in account.
  String get plexUserTitle => _p.getString('plexUserTitle') ?? '';
  String get plexUserUuid => _p.getString('plexUserUuid') ?? '';

  /// Saves the server and the token you signed in with. Resets any
  /// switched Home user back to the account itself.
  Future<void> setPlex(String url, String token, String library) async {
    final t = token.trim();
    await _p.setString('plexUrl', url.trim());
    if (t != plexAccountToken) {
      // A new sign-in: start as the account itself.
      await _p.setString('plexAccountToken', t);
      await _p.remove('plexUserTitle');
      await _p.remove('plexUserUuid');
      await _p.setString('plexToken', t);
    } else if (plexUserUuid.isEmpty) {
      await _p.setString('plexToken', t);
    } // else: same sign-in, keep the switched Home user's server token
    await _set('musicLibrary', library.trim());
  }

  /// Acts as a Plex Home user from now on, using [serverToken] for the server.
  Future<void> setPlexUser(String title, String uuid, String serverToken) async {
    if (_p.getString('plexAccountToken') == null) await _p.setString('plexAccountToken', plexToken);
    await _p.setString('plexUserTitle', title);
    await _p.setString('plexUserUuid', uuid);
    await _set('plexToken', serverToken);
  }

  set allowDelete(bool v) => _set('allowDelete', v);
  set allowSkip(bool v) => _set('allowSkip', v);
  set randomWhenEmpty(bool v) => _set('randomWhenEmpty', v);
  set artistSinglesMin(int v) => _set('artistSinglesMin', v);
  set mixedSinglesSize(int v) => _set('mixedSinglesSize', v);
  set albumMinTracks(int v) => _set('albumMinTracks', v);
  set cardsPerPage(int v) => _set('cardsPerPage', v);
  /// Tell the Plex server what's playing (Dashboard, Tautulli, play counts).
  bool get reportToPlex => _p.getBool('reportToPlex') ?? true;
  set reportToPlex(bool v) => _set('reportToPlex', v);

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
