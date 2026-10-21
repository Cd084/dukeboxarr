import 'dart:convert';

import 'package:http/http.dart' as http;

class PlexException implements Exception {
  final String message;
  PlexException(this.message);
  @override
  String toString() => message;
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

  static Map<String, String> headers(String clientId, [String? token]) => {
        'Accept': 'application/json',
        'X-Plex-Product': 'Dukebox',
        'X-Plex-Client-Identifier': clientId,
        if (token != null && token.isNotEmpty) 'X-Plex-Token': token,
      };

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

  String streamUrl(String partKey) => '$baseUrl$partKey?X-Plex-Token=$token';

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
