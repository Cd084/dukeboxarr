import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'library.dart';
import 'models.dart';
import 'settings.dart';

/// Picks the next few songs with a local LLM (Ollama), steered by the songs
/// people requested recently. Same approach as B-Side: a numbered candidate
/// list, a JSON-schema constrained reply of pick numbers, temperature 0.2,
/// thinking off.
class AiDj {
  final Settings settings;
  final Library library;
  final _rng = Random();
  final Map<String, ({bool thinking, int ctx})> _caps = {};

  AiDj(this.settings, this.library);

  static const _system = '''
You are the DJ for a jukebox. People in the room chose the "recently requested" songs.
From the numbered candidate list, pick exactly {k} songs to play next that fit the mood, style and energy of the recent requests, in a good listening order.
Vary the artists, and do not pick songs by the same artist back to back.

Return ONLY JSON in this exact form, using the numbers from the candidate list:
{"picks": [12, 3, 27]}

Rules:
- Exactly {k} numbers, each from the list, no duplicates.
- No titles, no explanations, no markdown - just the JSON object.''';

  static const _schema = {
    'type': 'object',
    'properties': {
      'picks': {'type': 'array', 'items': {'type': 'integer'}},
    },
    'required': ['picks'],
  };

  String get _base => settings.ollamaUrl;

  /// Model names installed on the Ollama host.
  Future<List<String>> models() async {
    final res = await http.get(Uri.parse('$_base/api/tags')).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Ollama returned ${res.statusCode}');
    return {for (final m in (jsonDecode(res.body)['models'] as List)) m['name'] as String}.toList()..sort();
  }

  Future<({bool thinking, int ctx})> _capabilities(String model) async {
    if (_caps[model] case final c?) return c;
    var thinking = false, ctx = 8192;
    try {
      final res = await http
          .post(Uri.parse('$_base/api/show'), body: jsonEncode({'name': model}))
          .timeout(const Duration(seconds: 15));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      thinking = ((j['capabilities'] as List?) ?? const []).contains('thinking');
      final info = (j['model_info'] as Map?) ?? const {};
      for (final MapEntry(:key, :value) in info.entries) {
        if (key.toString().endsWith('.context_length') && value is int) ctx = value;
      }
      final m = RegExp(r'num_ctx\s+(\d+)').firstMatch('${j['parameters'] ?? ''}');
      if (m != null) ctx = int.parse(m.group(1)!);
    } catch (e) {
      debugPrint('ollama /api/show failed: $e');
    }
    // A short prompt needs little context; keep it small so it loads fast.
    return _caps[model] = (thinking: thinking, ctx: min(ctx, 16384));
  }

  String _line(Song s) {
    String clip(String v) => v.length > 60 ? v.substring(0, 60) : v;
    final al = library.albums[s.albumKey];
    final meta = [
      if (al != null) clip(al.title),
      if (al?.year != null) '${al!.year}',
      if (library.genresOf(s).isNotEmpty) library.genresOf(s).take(2).join('/'),
    ].join(', ');
    return '${clip(s.artist)} - ${clip(s.title)}${meta.isEmpty ? '' : ' ($meta)'}';
  }

  /// Chooses [count] songs to follow [seeds]. Never returns songs in
  /// [exclude]. Throws on any failure so the caller can fall back.
  Future<List<Song>> pick(List<Song> seeds, Set<String> exclude, {int count = 5}) async {
    final model = settings.aiModel;
    if (model.isEmpty) throw Exception('No AI model selected');
    final caps = await _capabilities(model);

    // Candidate pool: songs sharing the seeds' genres (or anything, if the
    // seeds have none), minus recent plays. Shuffled, then packed to fit.
    final seedGenres = {for (final s in seeds) ...library.genresOf(s)};
    final seedKeys = {for (final s in seeds) s.key};
    var pool = library.songs.values
        .where((s) =>
            !exclude.contains(s.key) &&
            !seedKeys.contains(s.key) &&
            (seedGenres.isEmpty || library.genresOf(s).any(seedGenres.contains)))
        .toList();
    if (pool.length < count * 4) {
      pool = library.songs.values.where((s) => !exclude.contains(s.key) && !seedKeys.contains(s.key)).toList();
    }
    pool.shuffle(_rng);

    final seedText = [for (final s in seeds.take(20)) '- ${_line(s)}'].join('\n');
    final system = _system.replaceAll('{k}', '$count');
    // Token estimate ~ chars/3, as in B-Side. Leave room for the reply.
    var budget = (caps.ctx * 0.8).floor() - (system.length + seedText.length) ~/ 3 - 300;
    final candidates = <Song>[];
    final lines = StringBuffer();
    for (final s in pool) {
      final l = '${candidates.length + 1}. ${_line(s)}\n';
      budget -= l.length ~/ 3 + 1;
      if (budget < 0 || candidates.length >= 300) break;
      candidates.add(s);
      lines.write(l);
    }
    if (candidates.length < count) throw Exception('Not enough candidate songs');

    final prompt = 'Recently requested (most recent first):\n$seedText\n\n'
        'Candidates (1-${candidates.length}):\n$lines\n'
        'Choose $count of these ${candidates.length} songs. Reply with the JSON object only.';

    final res = await http
        .post(Uri.parse('$_base/api/generate'),
            body: jsonEncode({
              'model': model,
              'system': system,
              'prompt': prompt,
              'stream': false,
              'format': _schema,
              'keep_alive': '30m',
              if (caps.thinking) 'think': false,
              'options': {'temperature': 0.2, 'num_ctx': caps.ctx, 'num_predict': 256},
            }))
        .timeout(const Duration(seconds: 180));
    if (res.statusCode != 200) throw Exception('Ollama returned ${res.statusCode}: ${res.body}');

    final text = (jsonDecode(utf8.decode(res.bodyBytes))['response'] as String? ?? '')
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    final obj = RegExp(r'\{[\s\S]*\}').firstMatch(text)?.group(0);
    if (obj == null) throw Exception('AI reply had no JSON: $text');
    final decoded = jsonDecode(obj);
    final raw = decoded is Map ? (decoded['picks'] ?? decoded.values.whereType<List>().firstOrNull) : null;
    if (raw is! List) throw Exception('AI reply had no picks: $text');

    final out = <Song>[];
    for (final p in raw) {
      final n = p is int ? p : int.tryParse(RegExp(r'\d+').stringMatch('$p') ?? '');
      if (n == null || n < 1 || n > candidates.length) continue;
      final s = candidates[n - 1];
      if (!out.contains(s)) out.add(s);
      if (out.length == count) break;
    }
    if (out.isEmpty) throw Exception('AI returned no usable picks: $text');
    debugPrint('AI DJ ($model) picked: ${out.map((s) => '${s.artist} - ${s.title}').join(' | ')}');
    return out;
  }
}
