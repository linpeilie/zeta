import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// `general.json` v3 编解码。步骤 4 与旧 domain JSON 并行，生产 store 暂不调用。
final class GeneralSettingsCodec {
  const GeneralSettingsCodec();

  static const currentVersion = 3;

  Map<String, Object?> encode(GeneralSettings settings) {
    return <String, Object?>{
      'version': currentVersion,
      'sendMessageShortcut': switch (settings.sendMessageShortcut) {
        MessageSendShortcut.enter => 'enter',
        MessageSendShortcut.primaryModifierEnter => 'primaryModifierEnter',
      },
      'notifications': settings.notifications.toJson(),
      'appLanguage': settings.appLanguage.persistenceCode,
    };
  }

  /// [fallbackLanguage] 仅用于损坏或未知版本且无法识别语言时。
  GeneralSettings decode(Object? raw, {required AppLanguage fallbackLanguage}) {
    if (raw is! Map) {
      return GeneralSettings(appLanguage: fallbackLanguage);
    }
    final map = Map<Object?, Object?>.from(raw);
    final version = map['version'];
    if (version == 1 || version == 2) {
      return GeneralSettings(
        sendMessageShortcut: _decodeShortcut(map['sendMessageShortcut']),
        notifications: version == 2
            ? AgentNotificationSettings.tryDecode(map['notifications'])
            : const AgentNotificationSettings(),
        appLanguage: AppLanguage.simplifiedChinese,
      );
    }
    if (version == currentVersion) {
      return GeneralSettings(
        sendMessageShortcut: _decodeShortcut(map['sendMessageShortcut']),
        notifications: AgentNotificationSettings.tryDecode(
          map['notifications'],
        ),
        appLanguage:
            AppLanguagePersistence.tryParse(map['appLanguage']) ??
            AppLanguage.english,
      );
    }
    return GeneralSettings(
      sendMessageShortcut: _decodeShortcut(map['sendMessageShortcut']),
      notifications: AgentNotificationSettings.tryDecode(map['notifications']),
      appLanguage:
          AppLanguagePersistence.tryParse(map['appLanguage']) ??
          fallbackLanguage,
    );
  }

  MessageSendShortcut _decodeShortcut(Object? raw) {
    return switch (raw) {
      'primaryModifierEnter' => MessageSendShortcut.primaryModifierEnter,
      'enter' => MessageSendShortcut.enter,
      _ => MessageSendShortcut.enter,
    };
  }
}
