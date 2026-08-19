import 'package:meta/meta.dart';

/// Persisted message-send shortcut values.
enum MessageSendShortcutResponse {
  /// Sends when Enter is pressed.
  enter,

  /// Sends when the platform primary modifier and Enter are pressed.
  primaryModifierEnter,
}

/// Persisted application-language values.
enum AppLanguageResponse {
  /// English.
  english,

  /// Simplified Chinese.
  simplifiedChinese,
}

/// Persisted theme-mode values without a Flutter dependency.
enum AppearanceThemeModeResponse {
  /// Follows the operating-system theme.
  system,

  /// Uses the light theme.
  light,

  /// Uses the dark theme.
  dark,
}

/// Persisted appearance font-source values.
enum AppearanceFontChoiceKindResponse {
  /// Uses the platform default font.
  systemDefault,

  /// Uses an explicitly named system font.
  system,

  /// Uses the bundled JetBrains Mono font.
  bundledJetBrainsMono,
}

/// Provider-neutral persisted notification switches.
@immutable
final class AgentNotificationSettingsResponse {
  /// Creates notification settings.
  const AgentNotificationSettingsResponse({
    this.enabled = true,
    this.turnTerminalEnabled = true,
    this.actionRequiredEnabled = true,
  });

  /// Whether desktop notifications are enabled.
  final bool enabled;

  /// Whether terminal turn states may notify.
  final bool turnTerminalEnabled;

  /// Whether action-required states may notify.
  final bool actionRequiredEnabled;

  @override
  bool operator ==(Object other) {
    return other is AgentNotificationSettingsResponse &&
        other.enabled == enabled &&
        other.turnTerminalEnabled == turnTerminalEnabled &&
        other.actionRequiredEnabled == actionRequiredEnabled;
  }

  @override
  int get hashCode =>
      Object.hash(enabled, turnTerminalEnabled, actionRequiredEnabled);
}

/// Current-schema general-settings document value.
@immutable
final class GeneralSettingsResponse {
  /// Creates general settings.
  const GeneralSettingsResponse({
    this.sendMessageShortcut = MessageSendShortcutResponse.enter,
    this.notifications = const AgentNotificationSettingsResponse(),
    this.appLanguage = AppLanguageResponse.simplifiedChinese,
  });

  /// Persisted send shortcut.
  final MessageSendShortcutResponse sendMessageShortcut;

  /// Persisted notification switches.
  final AgentNotificationSettingsResponse notifications;

  /// Persisted next-launch language.
  final AppLanguageResponse appLanguage;

  @override
  bool operator ==(Object other) {
    return other is GeneralSettingsResponse &&
        other.sendMessageShortcut == sendMessageShortcut &&
        other.notifications == notifications &&
        other.appLanguage == appLanguage;
  }

  @override
  int get hashCode =>
      Object.hash(sendMessageShortcut, notifications, appLanguage);
}

/// One persisted appearance font choice.
@immutable
final class AppearanceFontChoiceResponse {
  /// Uses the application/platform default UI font.
  const AppearanceFontChoiceResponse.systemDefault()
    : kind = AppearanceFontChoiceKindResponse.systemDefault,
      fontFamily = null;

  /// Uses one explicitly selected system font [fontFamily].
  AppearanceFontChoiceResponse.system(String fontFamily)
    : kind = AppearanceFontChoiceKindResponse.system,
      fontFamily = _normalizedFamily(fontFamily);

  /// Uses the bundled JetBrains Mono family.
  const AppearanceFontChoiceResponse.bundledJetBrainsMono()
    : kind = AppearanceFontChoiceKindResponse.bundledJetBrainsMono,
      fontFamily = null;

  /// Persisted font-source kind.
  final AppearanceFontChoiceKindResponse kind;

  /// Canonical family when [kind] is system.
  final String? fontFamily;

  @override
  bool operator ==(Object other) {
    return other is AppearanceFontChoiceResponse &&
        other.kind == kind &&
        other.fontFamily == fontFamily;
  }

  @override
  int get hashCode => Object.hash(kind, fontFamily);
}

/// Minimum accepted UI font size in logical pixels.
const double minUiFontSize = 10;

/// Maximum accepted UI font size in logical pixels.
const double maxUiFontSize = 20;

/// Minimum accepted code font size in logical pixels.
const double minCodeFontSize = 10;

/// Maximum accepted code font size in logical pixels.
const double maxCodeFontSize = 24;

/// Current-schema appearance-settings document value.
@immutable
final class AppearanceSettingsResponse {
  /// Creates appearance settings.
  const AppearanceSettingsResponse({
    this.themeMode = AppearanceThemeModeResponse.system,
    this.uiFontChoice = const AppearanceFontChoiceResponse.systemDefault(),
    this.codeFontChoice =
        const AppearanceFontChoiceResponse.bundledJetBrainsMono(),
    this.uiFontSize = 12,
    this.codeFontSize = 12,
  });

  /// Persisted theme mode.
  final AppearanceThemeModeResponse themeMode;

  /// Persisted UI font choice.
  final AppearanceFontChoiceResponse uiFontChoice;

  /// Persisted code font choice.
  final AppearanceFontChoiceResponse codeFontChoice;

  /// Persisted UI font size.
  final double uiFontSize;

  /// Persisted code font size.
  final double codeFontSize;

  @override
  bool operator ==(Object other) {
    return other is AppearanceSettingsResponse &&
        other.themeMode == themeMode &&
        other.uiFontChoice == uiFontChoice &&
        other.codeFontChoice == codeFontChoice &&
        other.uiFontSize == uiFontSize &&
        other.codeFontSize == codeFontSize;
  }

  @override
  int get hashCode => Object.hash(
    themeMode,
    uiFontChoice,
    codeFontChoice,
    uiFontSize,
    codeFontSize,
  );
}

String _normalizedFamily(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'fontFamily', 'must not be empty');
  }
  return normalized;
}
