import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/settings/domain/app_language.dart';

/// 消息输入框使用的发送快捷键。
enum MessageSendShortcut {
  /// 无修饰键的 Enter 发送消息。
  enter,

  /// 平台主修饰键加 Enter 发送消息。
  ///
  /// Windows/Linux 使用 Ctrl，macOS 使用 Command。
  primaryModifierEnter,
}

/// Agent 系统通知的应用内分类开关。
@immutable
final class AgentNotificationSettings {
  const AgentNotificationSettings({
    this.enabled = true,
    this.turnTerminalEnabled = true,
    this.actionRequiredEnabled = true,
  });

  final bool enabled;
  final bool turnTerminalEnabled;
  final bool actionRequiredEnabled;

  AgentNotificationSettings copyWith({
    bool? enabled,
    bool? turnTerminalEnabled,
    bool? actionRequiredEnabled,
  }) {
    return AgentNotificationSettings(
      enabled: enabled ?? this.enabled,
      turnTerminalEnabled: turnTerminalEnabled ?? this.turnTerminalEnabled,
      actionRequiredEnabled:
          actionRequiredEnabled ?? this.actionRequiredEnabled,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'turnTerminalEnabled': turnTerminalEnabled,
    'actionRequiredEnabled': actionRequiredEnabled,
  };

  static AgentNotificationSettings tryDecode(Object? raw) {
    if (raw is! Map) {
      return const AgentNotificationSettings();
    }
    final map = Map<Object?, Object?>.from(raw);
    return AgentNotificationSettings(
      enabled: map['enabled'] is bool ? map['enabled']! as bool : true,
      turnTerminalEnabled: map['turnTerminalEnabled'] is bool
          ? map['turnTerminalEnabled']! as bool
          : true,
      actionRequiredEnabled: map['actionRequiredEnabled'] is bool
          ? map['actionRequiredEnabled']! as bool
          : true,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentNotificationSettings &&
        other.enabled == enabled &&
        other.turnTerminalEnabled == turnTerminalEnabled &&
        other.actionRequiredEnabled == actionRequiredEnabled;
  }

  @override
  int get hashCode =>
      Object.hash(enabled, turnTerminalEnabled, actionRequiredEnabled);
}

/// Zeta 的全局常规设置。
@immutable
class GeneralSettings {
  const GeneralSettings({
    this.sendMessageShortcut = MessageSendShortcut.enter,
    this.notifications = const AgentNotificationSettings(),
    this.appLanguage = AppLanguage.simplifiedChinese,
  });

  /// 消息输入框当前使用的发送快捷键。
  final MessageSendShortcut sendMessageShortcut;
  final AgentNotificationSettings notifications;

  /// 下次启动使用的界面语言。
  final AppLanguage appLanguage;

  GeneralSettings copyWith({
    MessageSendShortcut? sendMessageShortcut,
    AgentNotificationSettings? notifications,
    AppLanguage? appLanguage,
  }) {
    return GeneralSettings(
      sendMessageShortcut: sendMessageShortcut ?? this.sendMessageShortcut,
      notifications: notifications ?? this.notifications,
      appLanguage: appLanguage ?? this.appLanguage,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GeneralSettings &&
        other.sendMessageShortcut == sendMessageShortcut &&
        other.notifications == notifications &&
        other.appLanguage == appLanguage;
  }

  @override
  int get hashCode =>
      Object.hash(sendMessageShortcut, notifications, appLanguage);
}
