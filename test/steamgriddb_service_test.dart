import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/models/steamgriddb.dart';
import 'package:neostation/services/steamgriddb_service.dart';

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);

void main() {
  group('SteamGridDbService', () {
    test('sends the API key as a bearer token', () async {
      late http.Request seen;
      final service = SteamGridDbService(
        apiKey: 'abc123',
        client: MockClient((request) async {
          seen = request;
          return _ok([]);
        }),
      );

      await service.searchGames('Sonic');

      expect(seen.headers['Authorization'], 'Bearer abc123');
      expect(seen.url.host, 'www.steamgriddb.com');
      expect(seen.url.path, '/api/v2/search/autocomplete/Sonic');
    });

    test('encodes search terms as a single path segment', () async {
      late Uri seen;
      final service = SteamGridDbService(
        apiKey: 'k',
        client: MockClient((request) async {
          seen = request.url;
          return _ok([]);
        }),
      );

      await service.searchGames('Ratchet & Clank: Up/Down');

      expect(seen.pathSegments.last, 'Ratchet & Clank: Up/Down');
    });

    test('parses games with release years', () async {
      final service = SteamGridDbService(
        apiKey: 'k',
        client: MockClient(
          (_) async => _ok([
            {'id': 1, 'name': 'Half-Life', 'release_date': 910137600},
            {'id': 2, 'name': 'No Date'},
          ]),
        ),
      );

      final games = await service.searchGames('half');

      expect(games.map((g) => g.name), ['Half-Life', 'No Date']);
      expect(games.first.releaseYear, 1998);
      expect(games.last.releaseYear, isNull);
    });

    test('asks for static, safe, portrait grids for box art', () async {
      late Uri seen;
      final service = SteamGridDbService(
        apiKey: 'k',
        client: MockClient((request) async {
          seen = request.url;
          return _ok([
            {
              'id': 9,
              'url': 'https://cdn/full.png',
              'thumb': 'https://cdn/thumb.png',
              'width': 600,
              'height': 900,
            },
          ]);
        }),
      );

      final images = await service.getImages(42, SteamGridDbArtworkType.grid);

      expect(seen.path, '/api/v2/grids/game/42');
      expect(seen.queryParameters['types'], 'static');
      expect(seen.queryParameters['nsfw'], 'false');
      expect(seen.queryParameters['dimensions'], contains('600x900'));
      expect(images.single.thumbUrl, 'https://cdn/thumb.png');
      expect(images.single.aspectRatio, closeTo(600 / 900, 1e-9));
    });

    test('does not restrict hero or logo dimensions', () async {
      late Uri seen;
      final service = SteamGridDbService(
        apiKey: 'k',
        client: MockClient((request) async {
          seen = request.url;
          return _ok([]);
        }),
      );

      await service.getImages(42, SteamGridDbArtworkType.logo);

      expect(seen.path, '/api/v2/logos/game/42');
      expect(seen.queryParameters.containsKey('dimensions'), isFalse);
    });

    test('a rejected key is reported as unauthorized', () async {
      final service = SteamGridDbService(
        apiKey: 'bad',
        client: MockClient((_) async => http.Response('', 401)),
      );

      expect(
        service.validateKey(),
        throwsA(
          isA<SteamGridDbException>().having(
            (e) => e.kind,
            'kind',
            SteamGridDbErrorKind.unauthorized,
          ),
        ),
      );
    });

    test('a server error is reported as a network failure', () async {
      final service = SteamGridDbService(
        apiKey: 'k',
        client: MockClient((_) async => http.Response('', 500)),
      );

      expect(
        service.searchGames('x'),
        throwsA(
          isA<SteamGridDbException>().having(
            (e) => e.kind,
            'kind',
            SteamGridDbErrorKind.network,
          ),
        ),
      );
    });

    test('an unknown Steam app ID resolves to no game', () async {
      final service = SteamGridDbService(
        apiKey: 'k',
        client: MockClient((_) async => http.Response('', 404)),
      );

      expect(await service.gameForSteamAppId('999999999'), isNull);
    });
  });

  group('steamGridDbSearchTerm', () {
    test('drops No-Intro and Redump tags', () {
      expect(
        steamGridDbSearchTerm('Super Mario World (USA) (Rev 1) [!]'),
        'Super Mario World',
      );
    });

    test('moves a trailing article to the front', () {
      expect(
        steamGridDbSearchTerm('Legend of Zelda, The (Europe)'),
        'The Legend of Zelda',
      );
    });

    test('keeps a clean title as is', () {
      expect(steamGridDbSearchTerm('Half-Life 2'), 'Half-Life 2');
    });
  });

  group('SteamGridDbArtworkType', () {
    test('maps NeoStation media types', () {
      expect(
        SteamGridDbArtworkType.forMediaType('box2d'),
        SteamGridDbArtworkType.grid,
      );
      expect(
        SteamGridDbArtworkType.forMediaType('fanarts'),
        SteamGridDbArtworkType.hero,
      );
      expect(
        SteamGridDbArtworkType.forMediaType('wheels'),
        SteamGridDbArtworkType.logo,
      );
      expect(SteamGridDbArtworkType.forMediaType('screenshots'), isNull);
    });
  });
}
