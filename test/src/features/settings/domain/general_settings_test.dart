import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

void main() {
  test('defaults to Enter, enabled notifications and Chinese', () {
    const settings = GeneralSettings();

    expect(settings.sendMessageShortcut, MessageSendShortcut.enter);
    expect(settings.notifications, const AgentNotificationSettings());
    expect(settings.appLanguage, AppLanguage.simplifiedChinese);
  });

  test('copyWith can change language independently', () {
    const settings = GeneralSettings();

    expect(
      settings.copyWith(appLanguage: AppLanguage.english).appLanguage,
      AppLanguage.english,
    );
    expect(
      settings.copyWith(appLanguage: AppLanguage.english).sendMessageShortcut,
      MessageSendShortcut.enter,
    );
  });
}
