import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

void main() {
  test('defaults to Enter and enabled notification categories', () {
    const settings = GeneralSettings();

    expect(settings.sendMessageShortcut, MessageSendShortcut.enter);
    expect(settings.notifications, const AgentNotificationSettings());
    expect(settings.toJson(), <String, Object?>{
      'version': 2,
      'sendMessageShortcut': 'enter',
      'notifications': <String, Object?>{
        'enabled': true,
        'turnTerminalEnabled': true,
        'actionRequiredEnabled': true,
      },
    });
  });

  test('migrates version 1 while preserving the shortcut', () {
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
        'version': 3,
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

  test('decodes notification category switches from version 2', () {
    final settings = GeneralSettings.tryDecode(<String, Object?>{
      'version': 2,
      'sendMessageShortcut': 'primaryModifierEnter',
      'notifications': <String, Object?>{
        'enabled': true,
        'turnTerminalEnabled': false,
        'actionRequiredEnabled': true,
      },
    });

    expect(
      settings,
      const GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
        notifications: AgentNotificationSettings(turnTerminalEnabled: false),
      ),
    );
  });
}
