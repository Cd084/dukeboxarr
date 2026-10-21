import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browse.dart';
import '../models.dart';
import 'actions.dart';
import 'album_card.dart';
import 'keypad.dart';
import 'now_playing.dart';
import 'playlists.dart';
import 'search.dart';
import 'settings_screen.dart';
import 'theme.dart';

const _letters = ['#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _focus = FocusNode();
  Timer? _repeat;
  int _direction = 1;

  // Memoised split of the current entries into cards.
  List<Entry>? _partsFor;
  int _partsCap = 0;
  List<CardPart> _parts = const [];

  @override
  void dispose() {
    _repeat?.cancel();
    _focus.dispose();
    super.dispose();
  }

  List<CardPart> _split(List<Entry> entries, int cap) {
    if (identical(entries, _partsFor) && cap == _partsCap) return _parts;
    final out = <CardPart>[];
    for (final e in entries) {
      final n = (e.songs.length / cap).ceil();
      // Spread tracks evenly so a 13-track album on 12-row cards splits 7/6, not 12/1.
      final per = (e.songs.length / n).ceil();
      for (var i = 0; i < n; i++) {
        final start = i * per;
        final end = (start + per).clamp(0, e.songs.length);
        if (start < end) out.add(CardPart(e, start, end, i + 1, n));
      }
    }
    _partsFor = entries;
    _partsCap = cap;
    return _parts = out;
  }

  int _pageOf(List<CardPart> parts, Browse b, int perPage) {
    if (b.anchor == null) return 0;
    var idx = parts.indexWhere((p) => p.entry.id == b.anchor!.id && p.part == b.anchorPart);
    if (idx < 0) idx = parts.indexWhere((p) => p.entry.id == b.anchor!.id);
    return idx < 0 ? 0 : idx ~/ perPage;
  }

  void _goPage(int page, List<CardPart> parts, int perPage) {
    final pages = (parts.length / perPage).ceil();
    if (pages == 0) return;
    final p = page.clamp(0, pages - 1);
    final first = parts[p * perPage];
    AppScope.of(context).browse.setAnchor(first.entry, first.part);
  }

  void _goLetter(String letter, List<CardPart> parts, int perPage) {
    final idx = parts.indexWhere((p) {
      final c = p.entry.sortKey.isEmpty ? '' : p.entry.sortKey[0].toUpperCase();
      return letter == '#' ? !RegExp('[A-Z]').hasMatch(c) : c.compareTo(letter) >= 0;
    });
    if (idx >= 0) {
      _direction = 1;
      _goPage(idx ~/ perPage, parts, perPage);
    }
  }

  // Latest layout, so repeating page flips read the live position.
  List<CardPart> _curParts = const [];
  int _curPerPage = 4;

  void _step(int delta) {
    final b = AppScope.of(context).browse;
    final pages = (_curParts.length / _curPerPage).ceil();
    final next = _pageOf(_curParts, b, _curPerPage) + delta;
    if (next < 0 || next >= pages) {
      _repeat?.cancel();
      return;
    }
    _direction = delta;
    _goPage(next, _curParts, _curPerPage);
  }

  void _startRepeat(VoidCallback step) {
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 120), (_) => step());
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent ev, VoidCallback prev, VoidCallback next) {
    if (ev is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = ev.character;
    if (ch != null && RegExp(r'^\d$').hasMatch(ch)) {
      showKeypad(context, initial: ch);
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.arrowLeft || ev.logicalKey == LogicalKeyboardKey.pageUp) {
      prev();
      return KeyEventResult.handled;
    }
    if (ev.logicalKey == LogicalKeyboardKey.arrowRight || ev.logicalKey == LogicalKeyboardKey.pageDown) {
      next();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const NowPlayingBar(),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([app.browse, app.library, app.settings]),
                builder: (context, _) {
                  if (app.library.entries.isEmpty) return _emptyState(app);
                  return LayoutBuilder(builder: (context, box) => _grid(app, box));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(AppScope app) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (app.library.loading) ...[
            const CircularProgressIndicator(color: Jb.neon),
            const SizedBox(height: 20),
            Text(app.library.status, style: const TextStyle(color: Jb.neon, fontSize: 22)),
          ] else ...[
            Text(app.library.error ?? 'No music found',
                style: const TextStyle(color: Colors.redAccent, fontSize: 20)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => _openSettings(), child: const Text('OPEN SETTINGS')),
          ],
        ]),
      );

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  Widget _grid(AppScope app, BoxConstraints box) {
    const bottomBar = 84.0, filterBar = 48.0, gap = 14.0;
    final perPage = app.settings.cardsPerPage;
    final landscape = box.maxWidth > box.maxHeight;
    final rows = landscape ? (perPage > 4 ? 2 : 1) : (perPage > 2 ? 2 : 1);
    final cols = (perPage / rows).ceil();
    final gridH = box.maxHeight - bottomBar - (app.browse.isFiltered ? filterBar : 0) - gap * (rows + 1);
    final cap = trackCapacity(gridH / rows);

    final parts = _split(app.browse.entries, cap);
    final pages = (parts.length / perPage).ceil();
    final page = _pageOf(parts, app.browse, perPage);
    final onPage = parts.skip(page * perPage).take(perPage).toList();

    _curParts = parts;
    _curPerPage = perPage;
    void prev() => _step(-1);
    void next() => _step(1);

    final currentLetter = onPage.isEmpty
        ? ''
        : (() {
            final c = onPage.first.entry.sortKey.isEmpty ? '#' : onPage.first.entry.sortKey[0].toUpperCase();
            return RegExp('[A-Z]').hasMatch(c) ? c : '#';
          })();

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (n, e) => _onKey(n, e, prev, next),
      child: Column(
        children: [
          if (app.browse.isFiltered)
            Container(
              height: filterBar,
              color: Jb.cabinetHi,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Icon(Icons.filter_alt, color: Jb.neon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${app.browse.filterLabel}  —  ${app.browse.entries.length} selections',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Jb.neon, fontSize: 18)),
                ),
                TextButton.icon(
                    onPressed: app.browse.clearFilter, icon: const Icon(Icons.close), label: const Text('CLEAR FILTER')),
              ]),
            ),
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -200) next();
                if (v > 200) prev();
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) {
                  final incoming = child.key == ValueKey(page);
                  final dx = (incoming ? 0.15 : -0.15) * _direction;
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  key: ValueKey(page),
                  padding: const EdgeInsets.all(gap),
                  child: Column(
                    children: [
                      for (var r = 0; r < rows; r++) ...[
                        if (r > 0) const SizedBox(height: gap),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var c = 0; c < cols; c++) ...[
                                if (c > 0) const SizedBox(width: gap),
                                Expanded(
                                  child: r * cols + c < onPage.length
                                      ? AlbumCard(
                                          part: onPage[r * cols + c],
                                          onTrackTap: (s) => requestSong(context, s),
                                        )
                                      : const SizedBox(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: bottomBar,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(gap, 0, gap, gap),
              child: Row(
                children: [
                  _navButton(Icons.chevron_left, page > 0 ? prev : null),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              for (final l in _letters)
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _goLetter(l, parts, perPage),
                                    child: Center(
                                      child: Text(l,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: l == currentLetter ? Jb.neon : Jb.chrome.withValues(alpha: 0.6),
                                          )),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          onPage.isEmpty
                              ? ''
                              : 'Page ${page + 1} of $pages   ·   ${onPage.first.entry.code}–${onPage.last.entry.code}'
                                  '${app.library.syncing ? '   ·   syncing library…' : ''}',
                          style: const TextStyle(color: Jb.chrome, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _navButton(Icons.chevron_right, page < pages - 1 ? next : null),
                  const SizedBox(width: 16),
                  _toolButton(Icons.dialpad, 'KEYPAD', () => showKeypad(context)),
                  const SizedBox(width: 8),
                  _toolButton(Icons.search, 'SEARCH', () => openSearch(context)),
                  const SizedBox(width: 8),
                  _toolButton(Icons.playlist_play, 'PLAYLISTS', () => openPlaylists(context)),
                  const SizedBox(width: 8),
                  _toolButton(Icons.settings, '', _openSettings),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tap to flip one page; hold to flip continuously.
  Widget _navButton(IconData icon, VoidCallback? onTap) => GestureDetector(
        onLongPressStart: onTap == null ? null : (_) => _startRepeat(onTap),
        onLongPressEnd: (_) => _repeat?.cancel(),
        onLongPressCancel: () => _repeat?.cancel(),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 96,
            decoration: Jb.chromeButton(),
            child: Icon(icon, size: 52, color: onTap == null ? Colors.white24 : Jb.neon),
          ),
        ),
      );

  Widget _toolButton(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: Jb.chromeButton(),
          child: Row(children: [
            Icon(icon, size: 30, color: Jb.neon),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Jb.neon, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ]),
        ),
      );
}
