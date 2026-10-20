import 'package:flutter/widgets.dart';

import 'jukebox.dart';
import 'library.dart';
import 'models.dart';
import 'settings.dart';

/// What the album grid is showing: an optional filter plus the entry the
/// current page is anchored to (so the position survives resizes/re-filters).
class Browse extends ChangeNotifier {
  final Library library;
  Browse(this.library) {
    library.addListener(_invalidate);
  }

  Set<String> genres = {};
  String text = '';
  String? artist;
  Entry? anchor;
  int anchorPart = 1; // which card of a multi-card entry
  List<Entry>? _filtered;

  bool get isFiltered => genres.isNotEmpty || text.isNotEmpty || artist != null;

  String get filterLabel => [
        ?artist,
        if (text.isNotEmpty) '"$text"',
        ...genres,
      ].join(' · ');

  List<Entry> get entries => _filtered ??= _apply();

  List<Entry> _apply() {
    if (!isFiltered) return library.entries;
    final q = text.toLowerCase();
    return library.entries.where((e) {
      if (artist != null && e.artist != artist) return false;
      if (q.isNotEmpty &&
          !e.title.toLowerCase().contains(q) &&
          !e.artist.toLowerCase().contains(q) &&
          !e.songs.any((s) => s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q))) {
        return false;
      }
      if (genres.isNotEmpty && !e.songs.any((s) => library.genresOf(s).any(genres.contains))) {
        return false;
      }
      return true;
    }).toList();
  }

  void setFilter({Set<String>? genres, String? text, String? artist, bool clearArtist = false}) {
    if (genres != null) this.genres = genres;
    if (text != null) this.text = text.trim();
    if (artist != null || clearArtist) this.artist = artist;
    anchor = null;
    _invalidate();
  }

  void clearFilter() => setFilter(genres: {}, text: '', clearArtist: true);

  /// Shows [e] on the grid, clearing any filter that would hide it.
  void jumpTo(Entry e) {
    if (!entries.contains(e)) clearFilter();
    setAnchor(e);
  }

  void setAnchor(Entry? e, [int part = 1]) {
    anchor = e;
    anchorPart = part;
    notifyListeners();
  }

  void _invalidate() {
    _filtered = null;
    notifyListeners();
  }
}

/// Makes the app's controllers available to every widget.
class AppScope extends InheritedWidget {
  final Settings settings;
  final Library library;
  final Jukebox jukebox;
  final Browse browse;

  const AppScope({
    super.key,
    required this.settings,
    required this.library,
    required this.jukebox,
    required this.browse,
    required super.child,
  });

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => false;
}
