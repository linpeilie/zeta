import 'package:equatable/equatable.dart';
import 'package:settings_repository/settings_repository.dart';

export 'package:settings_repository/settings_repository.dart'
    show
        AppLanguage,
        MessageSendShortcut,
        SettingsFontChoice,
        SettingsRepositoryFailure,
        SettingsSnapshot,
        SettingsThemeMode;

enum SettingsStatus { initial, loading, ready, failure }

final class AppearanceFontOption extends Equatable {
  const AppearanceFontOption({
    required this.choice,
    required this.label,
    this.searchAliases = const <String>[],
  });

  const AppearanceFontOption.systemDefault()
    : choice = const SettingsFontChoice.systemDefault(),
      label = 'Geist',
      searchAliases = const <String>['Geist', 'system default'];

  const AppearanceFontOption.bundledJetBrainsMono()
    : choice = const SettingsFontChoice.bundledJetBrainsMono(),
      label = 'JetBrainsMono',
      searchAliases = const <String>['JetBrains Mono'];

  factory AppearanceFontOption.system(SettingsFontFamily family) {
    return AppearanceFontOption(
      choice: SettingsFontChoice.system(family.familyName),
      label: family.displayName,
      searchAliases: family.aliases,
    );
  }

  final SettingsFontChoice choice;
  final String label;
  final List<String> searchAliases;

  bool matches(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }
    return label.toLowerCase().contains(normalizedQuery) ||
        searchAliases.any(
          (alias) => alias.toLowerCase().contains(normalizedQuery),
        );
  }

  @override
  List<Object?> get props => <Object?>[choice, label, searchAliases];
}

final class SettingsState extends Equatable {
  const SettingsState({
    this.status = SettingsStatus.initial,
    this.snapshot = SettingsSnapshot.initial,
    this.appearanceDraft,
    this.uiFontOptions = const <AppearanceFontOption>[],
    this.codeFontOptions = const <AppearanceFontOption>[],
    this.languageRestartRequired = false,
    this.failure,
  });

  final SettingsStatus status;
  final SettingsSnapshot snapshot;
  final AppearanceSettings? appearanceDraft;
  final List<AppearanceFontOption> uiFontOptions;
  final List<AppearanceFontOption> codeFontOptions;
  final bool languageRestartRequired;
  final SettingsRepositoryFailure? failure;

  GeneralSettings get general => snapshot.general;

  AppearanceSettings get appearance => appearanceDraft ?? snapshot.appearance;

  SettingsState copyWith({
    SettingsStatus? status,
    SettingsSnapshot? snapshot,
    AppearanceSettings? appearanceDraft,
    List<AppearanceFontOption>? uiFontOptions,
    List<AppearanceFontOption>? codeFontOptions,
    bool? languageRestartRequired,
    SettingsRepositoryFailure? failure,
    bool clearAppearanceDraft = false,
    bool clearFailure = false,
  }) {
    return SettingsState(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      appearanceDraft: clearAppearanceDraft
          ? null
          : (appearanceDraft ?? this.appearanceDraft),
      uiFontOptions: uiFontOptions ?? this.uiFontOptions,
      codeFontOptions: codeFontOptions ?? this.codeFontOptions,
      languageRestartRequired:
          languageRestartRequired ?? this.languageRestartRequired,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    snapshot,
    appearanceDraft,
    uiFontOptions,
    codeFontOptions,
    languageRestartRequired,
    failure,
  ];
}
