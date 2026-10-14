import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/providers/romm_provider.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';
import 'package:neostation/repositories/romm_repository.dart';
import 'package:neostation/services/credential_store.dart';
import 'package:neostation/services/romm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_test_helper.dart';
import 'fake_credential_backends.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dbHelper = DatabaseTestHelper();
  late RommProvider provider;
  late List<String> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = await dbHelper.setUp();
    await db.execute(SqliteMigrations.createAppRommPlaySessionsTableSql);
    CredentialStore.debugUseBackends(
      secure: MemoryBackend(),
      file: MemoryBackend(),
    );
    provider = RommProvider();
    requests = [];
  });

  tearDown(() async {
    provider.dispose();
    RommService.debugUseHttpClient(null);
    CredentialStore.debugReset();
    await dbHelper.tearDown();
  });

  void serve(int userStatus) {
    RommService.debugUseHttpClient(
      MockClient((request) async {
        requests.add(request.url.path);
        if (request.url.path == '/api/token') {
          return http.Response(
            jsonEncode({
              'access_token': 'test-token',
              'refresh_token': 'test-refresh',
              'expires_in': 3600,
            }),
            200,
          );
        }
        if (request.url.path == '/api/users/me') {
          expect(request.headers['Authorization'], startsWith('Bearer '));
          return http.Response(
            jsonEncode({'username': 'testuser'}),
            userStatus,
          );
        }
        return http.Response('[]', 200);
      }),
    );
  }

  test('connect rejects a token that fails an authenticated request', () async {
    serve(403);
    expect(
      await provider.connect(
        serverUrl: 'https://romm.local',
        username: 'testuser',
        password: 'password',
      ),
      isNotNull,
    );
    expect(provider.status, RommConnectionStatus.error);
    expect(requests, contains('/api/users/me'));
    expect(await RommRepository.getConfig(), isNull);
  });

  test('connect verifies authentication before reporting success', () async {
    serve(200);
    expect(
      await provider.connect(
        serverUrl: 'https://romm.local',
        username: 'testuser',
        password: 'password',
      ),
      isNull,
    );
    expect(provider.status, RommConnectionStatus.connected);
    expect(requests, contains('/api/users/me'));
    expect(await RommRepository.getConfig(), isNotNull);
  });

  test(
    'restored credentials are verified and preserved on auth failure',
    () async {
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        apiKey: 'test-key',
      );
      serve(401);
      await provider.initialize();
      expect(provider.status, RommConnectionStatus.error);
      expect(provider.lastError, isNotNull);
      expect(requests, ['/api/users/me']);
      expect((await RommRepository.getConfig())!['api_key'], 'test-key');
    },
  );

  test('restored password connection verifies its cached token', () async {
    await RommRepository.saveConfig(
      serverUrl: 'https://romm.local',
      username: 'testuser',
      password: 'password',
    );
    await RommRepository.saveTokens(
      accessToken: 'cached-token',
      tokenExpires: DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    );
    serve(403);
    await provider.initialize();
    expect(provider.status, RommConnectionStatus.error);
    expect(requests.first, '/api/users/me');
    expect((await RommRepository.getConfig())!['password'], 'password');
  });
}
