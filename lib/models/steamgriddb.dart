/// A game entry on SteamGridDB, as returned by its search and lookup APIs.
class SteamGridDbGame {
  final int id;
  final String name;

  /// Release year, when SteamGridDB knows it.
  final int? releaseYear;

  const SteamGridDbGame({
    required this.id,
    required this.name,
    this.releaseYear,
  });

  factory SteamGridDbGame.fromJson(Map<String, dynamic> json) {
    // release_date is a Unix timestamp in seconds.
    final releaseDate = json['release_date'];
    int? year;
    if (releaseDate is num && releaseDate > 0) {
      year = DateTime.fromMillisecondsSinceEpoch(
        releaseDate.toInt() * 1000,
        isUtc: true,
      ).year;
    }
    return SteamGridDbGame(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      releaseYear: year,
    );
  }
}

/// One candidate image on SteamGridDB (a grid, hero or logo).
class SteamGridDbImage {
  final int id;

  /// Full-size image URL, downloaded when the user picks it.
  final String url;

  /// Small preview URL, shown in the picker grid.
  final String thumbUrl;

  final int width;
  final int height;

  const SteamGridDbImage({
    required this.id,
    required this.url,
    required this.thumbUrl,
    required this.width,
    required this.height,
  });

  factory SteamGridDbImage.fromJson(Map<String, dynamic> json) {
    final url = json['url']?.toString() ?? '';
    final thumb = json['thumb']?.toString();
    return SteamGridDbImage(
      id: (json['id'] as num).toInt(),
      url: url,
      thumbUrl: (thumb != null && thumb.isNotEmpty) ? thumb : url,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
    );
  }

  /// Width over height, falling back to 1 when SteamGridDB reports no size.
  double get aspectRatio => (width > 0 && height > 0) ? width / height : 1;
}

/// The SteamGridDB artwork kinds NeoStation can use, and the NeoStation media
/// folder each one replaces.
enum SteamGridDbArtworkType {
  /// Portrait grids, used as box art.
  grid('grids', 'box2d'),

  /// Wide banner art, used as fanart.
  hero('heroes', 'fanarts'),

  /// Transparent title logos, used as wheels.
  logo('logos', 'wheels');

  /// Path segment in the SteamGridDB API (`/grids/game/{id}`).
  final String apiPath;

  /// NeoStation media type this artwork is saved as.
  final String mediaType;

  const SteamGridDbArtworkType(this.apiPath, this.mediaType);

  /// The SteamGridDB type that supplies NeoStation's [mediaType], or null
  /// when SteamGridDB has nothing for it (screenshots).
  static SteamGridDbArtworkType? forMediaType(String mediaType) {
    for (final type in values) {
      if (type.mediaType == mediaType) return type;
    }
    return null;
  }
}

/// Turns a ROM-style title into a SteamGridDB search term.
///
/// No-Intro and Redump names carry tags such as `(USA)`, `(Rev 1)` or
/// `[!]` that SteamGridDB titles never have, and that make an autocomplete
/// search miss. Strips them, plus a trailing ", The" style article.
String steamGridDbSearchTerm(String title) {
  var term = title.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '');
  term = term.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final article = RegExp(r'^(.*), (The|A|An)$').firstMatch(term);
  if (article != null) term = '${article.group(2)} ${article.group(1)}';
  return term;
}
