/// Core data types. Kept free of Flutter imports so they can be built in an
/// isolate and serialised to the on-disk library cache.
library;

class Song {
  final String key; // Plex ratingKey
  final String title;
  final String artist; // track artist (falls back to album artist)
  final String albumKey;
  final String albumArtistKey;
  final int disc;
  final int index;
  final int durationMs;
  final String partKey; // /library/parts/... stream path

  const Song({
    required this.key,
    required this.title,
    required this.artist,
    required this.albumKey,
    required this.albumArtistKey,
    required this.disc,
    required this.index,
    required this.durationMs,
    required this.partKey,
  });

  Map<String, dynamic> toJson() => {
        'k': key, 't': title, 'a': artist, 'al': albumKey, 'ar': albumArtistKey,
        'd': disc, 'i': index, 'ms': durationMs, 'p': partKey,
      };

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        key: j['k'], title: j['t'], artist: j['a'], albumKey: j['al'],
        albumArtistKey: j['ar'], disc: j['d'], index: j['i'],
        durationMs: j['ms'], partKey: j['p'],
      );
}

class Album {
  final String key;
  final String title;
  final String artist;
  final String artistKey;
  final String artistSort;
  final int? year;
  final String? thumb;
  final List<String> genres;

  const Album({
    required this.key,
    required this.title,
    required this.artist,
    required this.artistKey,
    required this.artistSort,
    this.year,
    this.thumb,
    this.genres = const [],
  });

  Map<String, dynamic> toJson() => {
        'k': key, 't': title, 'a': artist, 'ak': artistKey, 's': artistSort,
        'y': year, 'th': thumb, 'g': genres,
      };

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        key: j['k'], title: j['t'], artist: j['a'], artistKey: j['ak'],
        artistSort: j['s'], year: j['y'], thumb: j['th'],
        genres: (j['g'] as List).cast<String>(),
      );
}

enum EntryKind { album, artistSingles, mixedSingles }

/// One numbered jukebox selection: an album, or a bundle of loose singles.
/// Track codes are `number` (4 digits) + position in [songs] (2 digits).
class Entry {
  final String id; // stable identity used for persisted numbering
  final EntryKind kind;
  final String title;
  final String artist;
  final String sortKey;
  final String? thumb;
  final int? year;
  final List<Song> songs; // max 99
  int number = 0;

  Entry({
    required this.id,
    required this.kind,
    required this.title,
    required this.artist,
    required this.sortKey,
    required this.songs,
    this.thumb,
    this.year,
  });

  String get code => number.toString().padLeft(4, '0');
  String trackCode(int i) => '$code${(i + 1).toString().padLeft(2, '0')}';
}

/// A slice of an entry that fits on one on-screen card.
class CardPart {
  final Entry entry;
  final int start; // index into entry.songs
  final int end; // exclusive
  final int part; // 1-based
  final int parts;
  const CardPart(this.entry, this.start, this.end, this.part, this.parts);
}

enum Source { request, random, ai }

/// A song placed in the queue / now playing, with how it got there.
class QueueItem {
  final Song song;
  final Entry? entry;
  final Source source;
  const QueueItem(this.song, this.entry, {this.source = Source.request});

  bool get random => source != Source.request;
}
