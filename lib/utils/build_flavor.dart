/// Build-time identity for side-by-side developer builds.
///
/// A build made with `--dart-define=NEOSTATION_FLAVOR=<name>` (for example
/// `pup`) gets its own app ID, display name, data folder and preferences, so
/// it can be installed and run next to the official release without sharing
/// any state. A build made without the define is the release and behaves
/// exactly as before.
///
/// The Android Gradle build (`android/app/build.gradle.kts`) and the macOS
/// Runner build phase read the same define, so the native app ID always
/// matches what the Dart code uses here.
class BuildFlavor {
  /// The flavor name, or an empty string for the release build.
  static const String name = String.fromEnvironment('NEOSTATION_FLAVOR');

  /// Whether this is a flavored (non-release) build.
  static bool get isFlavored => name.isNotEmpty;

  /// Base application ID shared by every platform.
  static const String baseAppId = 'com.neogamelab.neostation';

  /// Application ID for this build, e.g. `com.neogamelab.neostation.pup`.
  static String get appId => isFlavored ? '$baseAppId.$name' : baseAppId;

  /// Human-readable app name, e.g. `NeoStation Pup`.
  static String get displayName =>
      isFlavored ? 'NeoStation ${_capitalize(name)}' : 'NeoStation';

  /// Hidden data folder name in the home directory (Linux AppImage).
  static String get homeDataDirName =>
      isFlavored ? '.neostation-$name' : '.neostation';

  /// Prefix for SharedPreferences keys. Desktop platforms store preferences
  /// per vendor/product rather than per build, so a flavored build needs its
  /// own prefix to avoid reading the release build's settings (such as a
  /// custom user-data path).
  static String get sharedPreferencesPrefix =>
      isFlavored ? 'flutter.$name.' : 'flutter.';

  static String _capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}
