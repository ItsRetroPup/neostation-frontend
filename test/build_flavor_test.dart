import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/build_flavor.dart';

void main() {
  // Tests run without --dart-define, so they see the release identity. This
  // guards against a change that would alter the release build's IDs or paths.
  test('release build keeps the original identity', () {
    expect(BuildFlavor.isFlavored, isFalse);
    expect(BuildFlavor.appId, 'com.neogamelab.neostation');
    expect(BuildFlavor.displayName, 'NeoStation');
    expect(BuildFlavor.homeDataDirName, '.neostation');
    expect(BuildFlavor.sharedPreferencesPrefix, 'flutter.');
  });
}
