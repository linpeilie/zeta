import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

void main() {
  test('defaults to Enter and serializes a versioned payload', () {
    const settings = GeneralSettings();

    expect(settings.sendMessageShortcut, MessageSendShortcut.enter);
    expect(settings.toJson(), <String, Object?>{
      'version': 1,
      'sendMessageShortcut': 'enter',
    });
  });

  test('decodes primary modifier shortcut', () {
    final settings = GeneralSettings.tryDecode(<String, Object?>{
      'version': 1,
      'sendMessageShortcut': 'primaryModifierEnter',
    });

    expect(
      settings,
      const GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
      ),
    );
  });

  test('falls back to Enter for invalid versions and fields', () {
    expect(
      GeneralSettings.tryDecode(<String, Object?>{
        'version': 2,
        'sendMessageShortcut': 'primaryModifierEnter',
      }),
      const GeneralSettings(),
    );
    expect(
      GeneralSettings.tryDecode(<String, Object?>{
        'version': 1,
        'sendMessageShortcut': 'unknown',
      }),
      const GeneralSettings(),
    );
  });
}
