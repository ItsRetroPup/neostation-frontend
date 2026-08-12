import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/controller_glyphs.dart';

void main() {
  tearDown(() {
    ControllerGlyphProfileNotifier.profile.value = ControllerGlyphProfile.xbox;
  });

  test('selects PlayStation glyphs from a DualSense controller name', () {
    ControllerGlyphProfileNotifier.updateForControllerName('Sony - DualSense');

    expect(
      ControllerGlyphProfileNotifier.profile.value,
      ControllerGlyphProfile.playStation,
    );
  });

  test(
    'does not let an unknown placeholder reset a detected PlayStation pad',
    () {
      ControllerGlyphProfileNotifier.updateForControllerName(
        'Sony - DualSense',
      );
      ControllerGlyphProfileNotifier.updateForControllerName('Unknown device');

      expect(
        ControllerGlyphProfileNotifier.profile.value,
        ControllerGlyphProfile.playStation,
      );
    },
  );

  test('identifies the DualSense name emitted by gamepads_darwin', () {
    ControllerGlyphProfileNotifier.updateForControllerName(
      'DualSense Wireless Controller - DualSense',
    );

    expect(
      ControllerGlyphProfileNotifier.profile.value,
      ControllerGlyphProfile.playStation,
    );
  });

  test('maps the Xbox A hint to the real PlayStation cross PNG', () {
    expect(
      ControllerGlyphAssets.forProfile(
        'assets/images/gamepad/Xbox_A_button.png',
        ControllerGlyphProfile.playStation,
      ),
      'assets/images/gamepad/Ps_cross_button.png',
    );
  });
}
