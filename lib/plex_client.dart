import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class PlexException implements Exception {
  final String message;
  PlexException(this.message);
  @override
  String toString() => message;
}

class PlexPlayer {
  final String id; // clientIdentifier
  final String name;
  final String product;
  final List<String> uris; // direct control URLs, best first
  const PlexPlayer(this.id, this.name, this.product, this.uris);
}

/// Minimal Plex Media Server + plex.tv client.
class PlexClient {
  final String baseUrl;
  final String token;
  final String clientId;
  final http.Client _http;

  PlexClient(String url, this.token, this.clientId, {http.Client? client})
      : baseUrl = url.replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  /// App version, from pubspec.yaml; set at start-up in main().
  static String appVersion = '0.0.0';

  /// How this device appears in Plex (Dashboard, Tautulli, Authorized Devices).
  static Map<String, String> get device => {
    'X-Plex-Product': 'DukeBoxarr',
    'X-Plex-Version': appVersion,
    'X-Plex-Device': 'DukeBoxarr',
    // Header values must be ASCII.
    'X-Plex-Device-Name': 'DukeBoxarr (${Platform.localHostname.replaceAll(RegExp(r'[^\x20-\x7E]'), '')})',
    'X-Plex-Platform': switch (Platform.operatingSystem) {
      'windows' => 'Windows',
      'android' => 'Android',
      'linux' => 'Linux',
      'macos' => 'macOS',
      'ios' => 'iOS',
      final os => os,
    },
  };

  static Map<String, String> headers(String clientId, [String? token]) => {
        'Accept': 'application/json',
        ...device,
        'X-Plex-Client-Identifier': clientId,
        if (token != null && token.isNotEmpty) 'X-Plex-Token': token,
      };

  /// Reports local playback progress so the server shows a session
  /// (Dashboard, Tautulli) and counts plays. [state]: playing, paused, stopped.
  Future<void> reportTimeline(String songKey, String state, Duration time, Duration duration) async {
    final uri = Uri.parse('$baseUrl/:/timeline').replace(queryParameters: {
      'ratingKey': songKey,
      'key': '/library/metadata/$songKey',
      'state': state,
      'time': '${time.inMilliseconds}',
      'duration': '${duration.inMilliseconds}',
      'hasMDE': '1',
    });
    await _http.get(uri, headers: headers(clientId, token)).timeout(const Duration(seconds: 10));
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? extra}) async {
    final res = await _http
        .get(Uri.parse('$baseUrl$path'), headers: {...headers(clientId, token), ...?extra})
        .timeout(const Duration(seconds: 120));
    if (res.statusCode == 401) throw PlexException('Plex rejected the token (401)');
    if (res.statusCode != 200) throw PlexException('Plex returned ${res.statusCode} for $path');
    return (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['MediaContainer'] as Map<String, dynamic>;
  }

  /// Returns {title: sectionKey} for music libraries.
  Future<Map<String, String>> musicSections() async {
    final mc = await _get('/library/sections');
    return {
      for (final d in (mc['Directory'] as List? ?? const []))
        if (d['type'] == 'artist') d['title'] as String: d['key'].toString(),
    };
  }

  /// Fetches every item of [type] (8 artist, 9 album, 10 track) in pages.
  Future<List<Map<String, dynamic>>> all(String section, int type,
      {void Function(int done, int total)? progress}) async {
    const page = 5000;
    final out = <Map<String, dynamic>>[];
    var total = 1;
    while (out.length < total) {
      final mc = await _get('/library/sections/$section/all?type=$type', extra: {
        'X-Plex-Container-Start': '${out.length}',
        'X-Plex-Container-Size': '$page',
      });
      total = (mc['totalSize'] as int?) ?? (mc['size'] as int? ?? 0);
      final items = (mc['Metadata'] as List? ?? const []).cast<Map<String, dynamic>>();
      if (items.isEmpty) break;
      out.addAll(items);
      progress?.call(out.length, total);
    }
    return out;
  }

  /// Unique id of the server, to notice when the URL points somewhere new.
  Future<String?> machineId() async => (await _get('/identity'))['machineIdentifier'] as String?;

  /// Audio playlists: [{ratingKey, title, leafCount, composite, smart, duration}].
  Future<List<Map<String, dynamic>>> playlists() async =>
      ((await _get('/playlists?playlistType=audio'))['Metadata'] as List? ?? const [])
          .cast<Map<String, dynamic>>();

  /// Track ratingKeys of a playlist, in playlist order.
  Future<List<String>> playlistItemKeys(String key) async => [
        for (final m in ((await _get('/playlists/$key/items'))['Metadata'] as List? ?? const []))
          m['ratingKey'].toString()
      ];

  /// Plex players that can be remote-controlled: those the server sees on
  /// the LAN (/clients) plus those registered with plex.tv.
  Future<List<PlexPlayer>> players() async {
    final out = <String, PlexPlayer>{};
    void add(String? id, String? name, String? product, List<String> uris) {
      if (id == null || id == clientId) return;
      final prev = out[id];
      out[id] = PlexPlayer(id, prev?.name ?? name ?? 'Plex player', prev?.product ?? product ?? '',
          {...?prev?.uris, ...uris}.toList());
    }

    try {
      for (final s in ((await _get('/clients'))['Server'] as List? ?? const [])) {
        add(s['machineIdentifier'] as String?, s['name'] as String?, s['product'] as String?,
            ['http://${s['address']}:${s['port']}']);
      }
    } catch (_) {}
    try {
      final res = await _http
          .get(Uri.parse('https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1'),
              headers: headers(clientId, token))
          .timeout(const Duration(seconds: 15));
      for (final r in (jsonDecode(res.body) as List)) {
        if (!'${r['provides']}'.contains('player')) continue;
        final conns = (r['connections'] as List? ?? const []);
        add(r['clientIdentifier'] as String?, r['name'] as String?, r['product'] as String?, [
          for (final c in conns) if (c['local'] == true) c['uri'] as String,
          for (final c in conns) if (c['local'] != true) c['uri'] as String,
        ]);
      }
    } catch (_) {}
    return out.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Creates a one-song play queue for a remote player to load.
  Future<String> createPlayQueue(String songKey, String machineId) async {
    final uri = Uri.parse('$baseUrl/playQueues').replace(queryParameters: {
      'type': 'audio',
      'uri': 'server://$machineId/com.plexapp.plugins.library/library/metadata/$songKey',
      'shuffle': '0',
      'repeat': '0',
      'continuous': '0',
    });
    final res = await _http.post(uri, headers: headers(clientId, token)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw PlexException('Could not create play queue (${res.statusCode})');
    return (jsonDecode(res.body)['MediaContainer']['playQueueID']).toString();
  }

  /// The player can't send headers, so identity goes in the query string;
  /// that lets the server tie the stream to this client's timeline reports.
  String streamUrl(String partKey) => Uri.parse('$baseUrl$partKey').replace(queryParameters: {
        'X-Plex-Token': token,
        'X-Plex-Client-Identifier': clientId,
        'X-Plex-Product': device['X-Plex-Product']!,
        'X-Plex-Device-Name': device['X-Plex-Device-Name']!,
        'X-Plex-Platform': device['X-Plex-Platform']!,
      }).toString();

  String? artUrl(String? thumb, {int size = 300}) {
    if (thumb == null) return null;
    final t = Uri.encodeComponent(thumb);
    return '$baseUrl/photo/:/transcode?width=$size&height=$size&minSize=1&url=$t&X-Plex-Token=$token';
  }

  // ---- plex.tv PIN sign-in (user visits plex.tv/link and enters the code) ----

  static Future<({int id, String code})> createPin(String clientId) async {
    final res = await http.post(Uri.parse('https://plex.tv/api/v2/pins'),
        headers: headers(clientId));
    if (res.statusCode >= 300) throw PlexException('plex.tv PIN request failed (${res.statusCode})');
    final j = jsonDecode(res.body);
    return (id: j['id'] as int, code: j['code'] as String);
  }

  /// Returns the auth token once the PIN has been claimed, otherwise null.
  static Future<String?> checkPin(String clientId, int id) async {
    final res = await http.get(Uri.parse('https://plex.tv/api/v2/pins/$id'),
        headers: headers(clientId));
    if (res.statusCode >= 300) return null;
    final t = jsonDecode(res.body)['authToken'];
    return (t is String && t.isNotEmpty) ? t : null;
  }
}
