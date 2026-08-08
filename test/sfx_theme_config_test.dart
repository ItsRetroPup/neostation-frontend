import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/config_model.dart';

void main() {
  group('SFX theme configuration', () {
    test('defaults to the NeoStation theme', () {
      expect(ConfigModel().sfxTheme, 'NeoStation');
    });

    test('round-trips the selected theme through JSON persistence', () {
      final config = ConfigModel(sfxTheme: 'Maple');

      expect(ConfigModel.fromJson(config.toJson()).sfxTheme, 'Maple');
    });

    test('uses NeoStation when a saved configuration has no theme', () {
      expect(ConfigModel.fromJson(const {}).sfxTheme, 'NeoStation');
    });
  });
}
