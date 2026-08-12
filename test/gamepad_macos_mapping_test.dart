import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:neostation/utils/gamepad_translator.dart';

GamepadEvent _event(String id, String key, double value, KeyType type) {
  return GamepadEvent(
    gamepadId: id,
    timestamp: 0,
    type: type,
    key: key,
    value: value,
  );
}

void main() {
  test(
    'normalizes DualSense and Xbox GameController keys on macOS',
    () {
      final translator = GamepadEventTranslator();
      const dualSense = 'dualsense';
      const xbox = 'xbox';

      translator.updateGamepadName(dualSense, 'Sony - DualSense');
      translator.updateGamepadName(xbox, 'Microsoft - Xbox');

      expect(
        translator
            .translateEvent(
              _event(dualSense, 'xmark.circle', 1, KeyType.button),
            )
            ?.inputType,
        GamepadInputType.buttonA,
      );
      expect(
        translator
            .translateEvent(_event(xbox, 'a.circle', 1, KeyType.button))
            ?.inputType,
        GamepadInputType.buttonA,
      );
      expect(
        translator
            .translateEvent(_event(dualSense, 'dpad_y_axis', 1, KeyType.analog))
            ?.inputType,
        GamepadInputType.dpadUp,
      );
      expect(
        translator
            .translateEvent(
              _event(dualSense, 'left_thumbstick_x', 1, KeyType.analog),
            )
            ?.inputType,
        GamepadInputType.leftStickX,
      );
      expect(
        translator
            .translateEvent(_event(dualSense, 'select', 1, KeyType.button))
            ?.inputType,
        GamepadInputType.buttonSelect,
      );
    },
    skip: !Platform.isMacOS,
  );
}
