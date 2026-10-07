import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/steamgriddb.dart';
import 'package:neostation/screens/game_screen/game_settings_dialog/steamgriddb_picker_dialog.dart';
import 'package:neostation/services/steamgriddb_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Stub the gamepads plugin so GamepadNavigation.initialize() finds no
    // devices instead of relying on a real platform channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/gamepads'),
          (call) async => <dynamic>[],
        );
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1920, 1080)),
        child: ScreenUtilInit(
          designSize: const Size(1920, 1080),
          builder: (context, child) => MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: Builder(
              builder: (context) {
                ctx = context;
                return const Scaffold(body: SizedBox.shrink());
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return ctx;
  }

  /// Lets mock HTTP responses land and the dialog rebuild. Spinners animate
  /// forever, so pumpAndSettle would never return.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final grid = {
    'id': 77,
    'url': 'https://cdn.example/full.png',
    'thumb': 'https://cdn.example/thumb.png',
    'width': 600,
    'height': 900,
  };

  testWidgets('searches the cleaned title, then returns the tapped artwork', (
    tester,
  ) async {
    final paths = <String>[];
    final searches = <String>[];
    final service = SteamGridDbService(
      apiKey: 'k',
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.contains('/search/')) {
          searches.add(request.url.pathSegments.last);
          return _ok([
            {'id': 5, 'name': 'Super Mario World', 'release_date': 659318400},
          ]);
        }
        return _ok([grid]);
      }),
    );

    final ctx = await pumpHost(tester);
    SteamGridDbImage? picked;
    await tester.runAsync(() async {
      // ignore: unawaited_futures
      SteamGridDbPickerDialog.show(
        ctx,
        service: service,
        type: SteamGridDbArtworkType.grid,
        gameTitle: 'Super Mario World (USA)',
      ).then((image) => picked = image);
    });
    await settle(tester);

    expect(searches, ['Super Mario World']);
    expect(find.text('Choose the game'), findsOneWidget);
    expect(find.text('1990'), findsOneWidget);

    // The title also sits in the search field, so tap the row by its year.
    await tester.tap(find.text('1990'));
    await settle(tester);

    expect(paths.last, '/api/v2/grids/game/5');
    expect(find.text('Choose artwork for Super Mario World'), findsOneWidget);

    await tester.tap(find.byType(Image));
    await settle(tester);

    expect(find.byType(SteamGridDbPickerDialog), findsNothing);
    // The dialog's future was created under runAsync, so its completion runs
    // on the real event loop.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(picked?.id, 77);
    expect(picked?.url, 'https://cdn.example/full.png');
  });

  testWidgets('a Steam game opens its artwork straight from the app ID', (
    tester,
  ) async {
    final paths = <String>[];
    final service = SteamGridDbService(
      apiKey: 'k',
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.contains('/games/steam/')) {
          return _ok({'id': 9, 'name': 'Portal 2'});
        }
        return _ok([]);
      }),
    );

    final ctx = await pumpHost(tester);
    await tester.runAsync(() async {
      // ignore: unawaited_futures
      SteamGridDbPickerDialog.show(
        ctx,
        service: service,
        type: SteamGridDbArtworkType.logo,
        gameTitle: 'Portal 2',
        steamAppId: '620',
      );
    });
    await settle(tester);

    expect(paths, ['/api/v2/games/steam/620', '/api/v2/logos/game/9']);
    expect(find.text('Choose artwork for Portal 2'), findsOneWidget);
    expect(find.text('No artwork of this type for this game'), findsOneWidget);
  });
}
