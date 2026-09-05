import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 当前 `general.json` 编解码。
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

  /// [fallbackLanguage] 仅用于损坏或不支持版本的输入。
  GeneralSettings decode(Object? raw, {required AppLanguage fallbackLanguage}) {
    if (raw is! Map) {
      return GeneralSettings(appLanguage: fallbackLanguage);
    }
    final map = Map<Object?, Object?>.from(raw);
    if (map['version'] != currentVersion) {
      return GeneralSettings(appLanguage: fallbackLanguage);
    }
    return GeneralSettings(
      sendMessageShortcut: _decodeShortcut(map['sendMessageShortcut']),
      notifications: AgentNotificationSettings.tryDecode(map['notifications']),
      appLanguage:
          AppLanguagePersistence.tryParse(map['appLanguage']) ??
          AppLanguage.english,
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
