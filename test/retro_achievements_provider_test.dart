import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';

void main() {
  test('top-ten loading is guarded while signed out', () async {
    final provider = RetroAchievementsProvider();
    addTearDown(provider.dispose);

    expect(await provider.loadTopTenUsers(), isFalse);
    expect(provider.topTenUsers, isEmpty);
    expect(provider.topTenUsersLoaded, isFalse);
    expect(provider.topTenUsersLoading, isFalse);
  });
}
