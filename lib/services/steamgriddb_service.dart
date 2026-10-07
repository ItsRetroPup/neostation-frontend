import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/steamgriddb.dart';
import '../repositories/steamgriddb_repository.dart';
import 'logger_service.dart';

/// Why a SteamGridDB request failed.
enum SteamGridDbErrorKind {
  /// The API key is missing, wrong or revoked (HTTP 401/403).
  unauthorized,

  /// The requested game or resource does not exist (HTTP 404).
  notFound,

  /// No connection, a timeout, or a server error.
  network,
}

class SteamGridDbException implements Exception {
  final SteamGridDbErrorKind kind;
  final String message;

  const SteamGridDbException(this.kind, this.message);

  @override
  String toString() => 'SteamGridDbException(${kind.name}): $message';
}

/// Client for the SteamGridDB v2 API (https://www.steamgriddb.com/api/v2).
///
/// SteamGridDB is a manual, supplementary artwork source: nothing here runs
/// during a ScreenScraper scrape. The user opens it from a game's settings,
/// picks the game and an image, and that image replaces one media file.
class SteamGridDbService {
  static const String _host = 'www.steamgriddb.com';
  static const String _basePath = '/api/v2';
  static const Duration _timeout = Duration(seconds: 15);

  /// Portrait grid sizes. SteamGridDB grids also come in landscape and square
  /// shapes, which would not fit a box art slot.
  static const String _portraitGridDimensions = '600x900,342x482,660x930';

  static final _log = LoggerService.instance;

  final String apiKey;
  final http.Client _client;

  SteamGridDbService({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  /// A service using the stored API key, or null when none is set.
  static Future<SteamGridDbService?> fromStoredKey() async {
    final key = await SteamGridDbRepository.getApiKey();
    return key == null ? null : SteamGridDbService(apiKey: key);
  }

  /// Checks that [apiKey] is accepted, with a cheap search request.
  ///
  /// Throws [SteamGridDbException] with [SteamGridDbErrorKind.unauthorized]
  /// for a rejected key, or [SteamGridDbErrorKind.network] when SteamGridDB
  /// could not be reached (so the caller can tell the two apart).
  Future<void> validateKey() async {
    await _getJsonOrNull(['search', 'autocomplete', 'test']);
  }

  /// Games whose name matches [term], best match first.
  Future<List<SteamGridDbGame>> searchGames(String term) async {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return const [];
    final data = await _getJsonOrNull(['search', 'autocomplete', trimmed]);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(SteamGridDbGame.fromJson)
        .toList();
  }

  /// The SteamGridDB game for a Steam [appId], or null when there is none.
  Future<SteamGridDbGame?> gameForSteamAppId(String appId) async {
    try {
      final data = await _getJson(['games', 'steam', appId]);
      return data is Map<String, dynamic>
          ? SteamGridDbGame.fromJson(data)
          : null;
    } on SteamGridDbException catch (e) {
      // An unknown app ID is "no match", not a failure.
      if (e.kind == SteamGridDbErrorKind.notFound) return null;
      rethrow;
    }
  }

  /// Static (non-animated), safe-for-work images of [type] for [gameId].
  Future<List<SteamGridDbImage>> getImages(
    int gameId,
    SteamGridDbArtworkType type,
  ) async {
    final query = <String, String>{
      'types': 'static',
      'nsfw': 'false',
      'humor': 'false',
      if (type == SteamGridDbArtworkType.grid)
        'dimensions': _portraitGridDimensions,
    };
    final data = await _getJsonOrNull([type.apiPath, 'game', '$gameId'], query);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(SteamGridDbImage.fromJson)
        .where((image) => image.url.isNotEmpty)
        .toList();
  }

  /// Downloads a full-size image picked from [getImages].
  Future<Uint8List> downloadImage(String url) async {
    try {
      final response = await _client.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw SteamGridDbException(
          SteamGridDbErrorKind.network,
          'Image download failed: HTTP ${response.statusCode}',
        );
      }
      return response.bodyBytes;
    } on SteamGridDbException {
      rethrow;
    } on Exception catch (e) {
      throw SteamGridDbException(SteamGridDbErrorKind.network, e.toString());
    }
  }

  void close() => _client.close();

  /// Like [_getJson], but a 404 (nothing found) yields null.
  Future<Object?> _getJsonOrNull(
    List<String> segments, [
    Map<String, String>? query,
  ]) async {
    try {
      return await _getJson(segments, query);
    } on SteamGridDbException catch (e) {
      if (e.kind == SteamGridDbErrorKind.notFound) return null;
      rethrow;
    }
  }

  /// GETs an API path and returns the `data` member of the response.
  Future<Object?> _getJson(
    List<String> segments, [
    Map<String, String>? query,
  ]) async {
    final uri = Uri(
      scheme: 'https',
      host: _host,
      pathSegments: [
        ..._basePath.split('/').where((s) => s.isNotEmpty),
        ...segments,
      ],
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'Authorization': 'Bearer $apiKey'})
          .timeout(_timeout);
    } on TimeoutException catch (e) {
      throw SteamGridDbException(SteamGridDbErrorKind.network, e.toString());
    } on SocketException catch (e) {
      throw SteamGridDbException(SteamGridDbErrorKind.network, e.toString());
    } on http.ClientException catch (e) {
      throw SteamGridDbException(SteamGridDbErrorKind.network, e.toString());
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SteamGridDbException(
        SteamGridDbErrorKind.unauthorized,
        'API key rejected',
      );
    }
    if (response.statusCode == 404) {
      throw const SteamGridDbException(
        SteamGridDbErrorKind.notFound,
        'Not found',
      );
    }
    if (response.statusCode != 200) {
      _log.w('SteamGridDB: HTTP ${response.statusCode} for ${uri.path}');
      throw SteamGridDbException(
        SteamGridDbErrorKind.network,
        'HTTP ${response.statusCode}',
      );
    }

    try {
      final body = json.decode(response.body);
      if (body is Map<String, dynamic> && body['success'] == true) {
        return body['data'];
      }
    } on FormatException catch (e) {
      _log.w('SteamGridDB: unreadable response for ${uri.path}: $e');
    }
    throw const SteamGridDbException(
      SteamGridDbErrorKind.network,
      'Unexpected response',
    );
  }
}
