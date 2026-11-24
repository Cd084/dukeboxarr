// ignore_for_file: avoid_print
// Live check of Plex Home user switching against a real account/server.
// Skipped unless DUKEBOX_LIVE=1. Uses the settings saved by the Windows app.
//   $env:DUKEBOX_LIVE=1; $env:SWITCH_TO='<profile name>'; flutter test test/plex_home_live_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:dukebox/plex_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final live = Platform.environment['DUKEBOX_LIVE'] == '1';

  test('switch to a Plex Home user and read the library as them', () async {
    final prefs = jsonDecode(await File(
            '${Platform.environment['APPDATA']}/ca.dukebox/dukebox/shared_preferences.json')
        .readAsString()) as Map<String, dynamic>;
    final clientId = prefs['flutter.clientId'] as String;
    final account = (prefs['flutter.plexAccountToken'] ?? prefs['flutter.plexToken']) as String;
    final url = prefs['flutter.plexUrl'] as String;
    final serverId = prefs['flutter.serverId'] as String;

    final users = await PlexClient.homeUsers(clientId, account);
    print('Home users: ${users.map((u) => '${u.title}${u.protected ? ' (PIN)' : ''}').join(', ')}');
    final want = Platform.environment['SWITCH_TO'];
    final target = want == null ? users.firstWhere((u) => !u.admin, orElse: () => users.first) : users.firstWhere((u) => u.title == want);

    final token = await PlexClient.switchHomeUser(clientId, account, target.uuid, serverId);
    final sections = await PlexClient(url, token, clientId).musicSections();
    print('${target.title} sees music libraries: ${sections.keys.join(', ')}');
    expect(sections, isNotEmpty);
  }, skip: !live);
}
