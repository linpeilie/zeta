import 'package:flutter/foundation.dart';

/// 消息输入框使用的发送快捷键。
enum MessageSendShortcut {
  /// 无修饰键的 Enter 发送消息。
  enter,

  /// 平台主修饰键加 Enter 发送消息。
  ///
  /// Windows/Linux 使用 Ctrl，macOS 使用 Command。
  primaryModifierEnter,
}

/// Zeta 的全局常规设置。
@immutable
class GeneralSettings {
  const GeneralSettings({this.sendMessageShortcut = MessageSendShortcut.enter});

  /// 消息输入框当前使用的发送快捷键。
  final MessageSendShortcut sendMessageShortcut;

  GeneralSettings copyWith({MessageSendShortcut? sendMessageShortcut}) {
    return GeneralSettings(
      sendMessageShortcut: sendMessageShortcut ?? this.sendMessageShortcut,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': 1,
      'sendMessageShortcut': switch (sendMessageShortcut) {
        MessageSendShortcut.enter => 'enter',
        MessageSendShortcut.primaryModifierEnter => 'primaryModifierEnter',
      },
    };
  }

  /// 容错解析持久化内容；未知版本或字段回退到默认设置。
  static GeneralSettings tryDecode(Object? raw) {
    if (raw is! Map) {
      return const GeneralSettings();
    }
    final map = Map<Object?, Object?>.from(raw);
    if (map['version'] != 1) {
      return const GeneralSettings();
    }
    return GeneralSettings(
      sendMessageShortcut: switch (map['sendMessageShortcut']) {
        'primaryModifierEnter' => MessageSendShortcut.primaryModifierEnter,
        'enter' => MessageSendShortcut.enter,
        _ => MessageSendShortcut.enter,
      },
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GeneralSettings &&
        other.sendMessageShortcut == sendMessageShortcut;
  }

  @override
  int get hashCode => sendMessageShortcut.hashCode;
}
