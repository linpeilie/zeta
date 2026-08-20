import 'package:equatable/equatable.dart';

/// Message-send shortcuts supported by the application domain.
enum MessageSendShortcut {
  /// Sends when Enter is pressed.
  enter,

  /// Sends when the platform primary modifier and Enter are pressed.
  primaryModifierEnter,
}

/// Application languages supported by the first current schema.
enum AppLanguage {
  /// English.
  english,

  /// Simplified Chinese.
  simplifiedChinese,
}

/// Resolves the initial language from the first system locale components.
///
/// This pure function deliberately accepts no Flutter `Locale` object.
AppLanguage resolveAppLanguageFromFirstSystemLocale({
  String? languageCode,
  String? scriptCode,
  String? countryCode,
}) {
  final language = languageCode?.trim().toLowerCase();
  if (language == null || language.isEmpty || language == 'en') {
    return AppLanguage.english;
  }
  if (language != 'zh') {
    return AppLanguage.english;
  }
  final script = scriptCode?.trim().toLowerCase();
  if (script == 'hant') {
    return AppLanguage.english;
  }
  if (script == 'hans') {
    return AppLanguage.simplifiedChinese;
  }
  final region = countryCode?.trim().toUpperCase();
  if (region == 'TW' || region == 'HK' || region == 'MO') {
    return AppLanguage.english;
  }
  if (region == 'CN' || region == 'SG' || region == null || region.isEmpty) {
    return AppLanguage.simplifiedChinese;
  }
  return AppLanguage.english;
}

/// Provider-neutral desktop notification switches.
final class AgentNotificationSettings extends Equatable {
  /// Creates notification settings.
  const AgentNotificationSettings({
    this.enabled = true,
    this.turnTerminalEnabled = true,
    this.actionRequiredEnabled = true,
  });

  /// Whether desktop notifications are globally enabled.
  final bool enabled;

  /// Whether terminal turn states may notify.
  final bool turnTerminalEnabled;

  /// Whether action-required states may notify.
  final bool actionRequiredEnabled;

  /// Returns a copy with selected values replaced.
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

  @override
  List<Object?> get props => <Object?>[
    enabled,
    turnTerminalEnabled,
    actionRequiredEnabled,
  ];
}

/// Current general application settings.
final class GeneralSettings extends Equatable {
  /// Creates general settings.
  const GeneralSettings({
    this.sendMessageShortcut = MessageSendShortcut.enter,
    this.notifications = const AgentNotificationSettings(),
    this.appLanguage = AppLanguage.simplifiedChinese,
  });

  /// Message-send shortcut.
  final MessageSendShortcut sendMessageShortcut;

  /// Desktop notification switches.
  final AgentNotificationSettings notifications;

  /// Language used at the next application launch.
  final AppLanguage appLanguage;

  /// Returns a copy with selected values replaced.
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
  List<Object?> get props => <Object?>[
    sendMessageShortcut,
    notifications,
    appLanguage,
  ];
}

/// Theme-mode values without a Flutter dependency.
enum SettingsThemeMode {
  /// Follows the operating-system theme.
  system,

  /// Uses the light theme.
  light,

  /// Uses the dark theme.
  dark,
}

/// Appearance font-source values.
enum SettingsFontChoiceKind {
  /// Uses the application/platform default UI font.
  systemDefault,

  /// Uses an explicitly named system font.
  system,

  /// Uses the bundled JetBrains Mono font.
  bundledJetBrainsMono,
}

/// One persisted appearance font choice.
final class SettingsFontChoice extends Equatable {
  /// Uses the application/platform default UI font.
  const SettingsFontChoice.systemDefault()
    : kind = SettingsFontChoiceKind.systemDefault,
      fontFamily = null;

  /// Uses one explicitly selected system [fontFamily].
  SettingsFontChoice.system(String fontFamily)
    : kind = SettingsFontChoiceKind.system,
      fontFamily = _nonEmpty(fontFamily, 'fontFamily');

  /// Uses the bundled JetBrains Mono family.
  const SettingsFontChoice.bundledJetBrainsMono()
    : kind = SettingsFontChoiceKind.bundledJetBrainsMono,
      fontFamily = null;

  /// Persisted font-source kind.
  final SettingsFontChoiceKind kind;

  /// Canonical family when [kind] is [SettingsFontChoiceKind.system].
  final String? fontFamily;

  /// Whether this is the application/platform default choice.
  bool get isSystemDefault => kind == SettingsFontChoiceKind.systemDefault;

  /// Whether this is an explicit system family.
  bool get isSystemFont => kind == SettingsFontChoiceKind.system;

  /// Whether this is the bundled code family.
  bool get isBundledJetBrainsMono =>
      kind == SettingsFontChoiceKind.bundledJetBrainsMono;

  /// Stable identity for caches and keys.
  String get stableId => switch (kind) {
    SettingsFontChoiceKind.systemDefault => 'system-default',
    SettingsFontChoiceKind.system => 'system-$fontFamily',
    SettingsFontChoiceKind.bundledJetBrainsMono => 'bundled-jetbrains-mono',
  };

  @override
  List<Object?> get props => <Object?>[kind, fontFamily];
}

/// Minimum accepted UI font size in logical pixels.
const double minUiFontSize = 10;

/// Maximum accepted UI font size in logical pixels.
const double maxUiFontSize = 20;

/// Minimum accepted code font size in logical pixels.
const double minCodeFontSize = 10;

/// Maximum accepted code font size in logical pixels.
const double maxCodeFontSize = 24;

/// Current appearance settings without Flutter presentation types.
final class AppearanceSettings extends Equatable {
  /// Creates appearance settings.
  const AppearanceSettings({
    this.themeMode = SettingsThemeMode.system,
    this.uiFontChoice = const SettingsFontChoice.systemDefault(),
    this.codeFontChoice = const SettingsFontChoice.bundledJetBrainsMono(),
    this.uiFontSize = 12,
    this.codeFontSize = 12,
  }) : assert(
         uiFontSize >= minUiFontSize && uiFontSize <= maxUiFontSize,
         'uiFontSize must be within the current-schema range',
       ),
       assert(
         codeFontSize >= minCodeFontSize && codeFontSize <= maxCodeFontSize,
         'codeFontSize must be within the current-schema range',
       );

  /// Current theme mode.
  final SettingsThemeMode themeMode;

  /// Current UI font choice.
  final SettingsFontChoice uiFontChoice;

  /// Current code font choice.
  final SettingsFontChoice codeFontChoice;

  /// Base UI font size.
  final double uiFontSize;

  /// Base code font size.
  final double codeFontSize;

  /// Returns a copy with selected values replaced.
  AppearanceSettings copyWith({
    SettingsThemeMode? themeMode,
    SettingsFontChoice? uiFontChoice,
    SettingsFontChoice? codeFontChoice,
    double? uiFontSize,
    double? codeFontSize,
  }) {
    return AppearanceSettings(
      themeMode: themeMode ?? this.themeMode,
      uiFontChoice: uiFontChoice ?? this.uiFontChoice,
      codeFontChoice: codeFontChoice ?? this.codeFontChoice,
      uiFontSize: uiFontSize ?? this.uiFontSize,
      codeFontSize: codeFontSize ?? this.codeFontSize,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    themeMode,
    uiFontChoice,
    codeFontChoice,
    uiFontSize,
    codeFontSize,
  ];
}

/// Immutable external-data snapshot exposed by the settings Repository.
final class SettingsSnapshot extends Equatable {
  /// Creates a settings snapshot.
  const SettingsSnapshot({
    required this.general,
    required this.appearance,
    required this.revision,
  });

  /// Initial value exposed before the persistence stores finish loading.
  static const initial = SettingsSnapshot(
    general: GeneralSettings(),
    appearance: AppearanceSettings(),
    revision: 0,
  );

  /// Current general settings.
  final GeneralSettings general;

  /// Current appearance settings.
  final AppearanceSettings appearance;

  /// Monotonically increasing in-memory revision.
  final int revision;

  @override
  List<Object?> get props => <Object?>[general, appearance, revision];
}

/// One platform-neutral system font family.
final class SettingsFontFamily extends Equatable {
  /// Creates a normalized system font family.
  SettingsFontFamily({
    required String id,
    required String familyName,
    required String displayName,
    required Iterable<String> aliases,
    required this.isMonospace,
  }) : id = _nonEmpty(id, 'id'),
       familyName = _nonEmpty(familyName, 'familyName'),
       displayName = _nonEmpty(displayName, 'displayName'),
       aliases = List<String>.unmodifiable(
         aliases.map((alias) => _nonEmpty(alias, 'aliases')),
       );

  /// Stable platform-qualified identity.
  final String id;

  /// Canonical family used by the text engine and persistence.
  final String familyName;

  /// Locale-sensitive display name supplied by the platform.
  final String displayName;

  /// Alternative family or legacy file names.
  final List<String> aliases;

  /// Whether the platform reports a fixed-width family.
  final bool isMonospace;

  @override
  List<Object?> get props => <Object?>[
    id,
    familyName,
    displayName,
    aliases,
    isMonospace,
  ];
}

/// A single-document settings update accepted by the Repository.
sealed class SettingsUpdate extends Equatable {
  const SettingsUpdate();
}

/// Replaces the current general-settings document.
final class GeneralSettingsUpdate extends SettingsUpdate {
  /// Creates a general-settings update.
  const GeneralSettingsUpdate(this.value);

  /// Replacement value.
  final GeneralSettings value;

  @override
  List<Object?> get props => <Object?>[value];
}

/// Replaces the current appearance-settings document.
final class AppearanceSettingsUpdate extends SettingsUpdate {
  /// Creates an appearance-settings update.
  const AppearanceSettingsUpdate(this.value);

  /// Replacement value.
  final AppearanceSettings value;

  @override
  List<Object?> get props => <Object?>[value];
}

/// Successful settings persistence outcomes.
enum SettingsPersistResult {
  /// The requested document was already current and no write occurred.
  unchanged,

  /// Persistence succeeded and a new snapshot was published.
  applied,
}

String _nonEmpty(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}
