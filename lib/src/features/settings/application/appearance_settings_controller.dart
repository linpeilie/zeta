import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/system_font_family.dart';

final _log = loggerFor('zeta.settings.appearance_controller');

/// 字体选择弹窗使用的展示选项。
@immutable
class AppearanceFontOption {
  const AppearanceFontOption({
    required this.choice,
    required this.label,
    this.searchAliases = const <String>[],
  });

  factory AppearanceFontOption.system(SystemFontFamily family) {
    return AppearanceFontOption(
      choice: AppearanceFontChoice.system(family.familyName),
      label: family.displayName,
      searchAliases: family.aliases,
    );
  }

  const AppearanceFontOption.systemDefault()
    : choice = const AppearanceFontChoice.systemDefault(),
      label = '系统默认',
      searchAliases = const <String>[];

  const AppearanceFontOption.bundledJetBrainsMono()
    : choice = const AppearanceFontChoice.bundledJetBrainsMono(),
      label = 'JetBrainsMono（内置默认）',
      searchAliases = const <String>['JetBrains Mono'];

  final AppearanceFontChoice choice;
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
}

/// 全局外观设置控制器。
///
/// 负责外观偏好加载、持久化以及系统字体目录解析。
class AppearanceSettingsController extends ChangeNotifier {
  AppearanceSettingsController({
    required this.store,
    required this.fontCatalog,
  });

  final AppearanceSettingsStore store;
  final SystemFontCatalogService fontCatalog;

  AppearanceSettings _settings = const AppearanceSettings();
  Future<AppearanceSettings>? _loadFuture;
  bool _disposed = false;
  final Map<String, String> _fontDisplayNames = <String, String>{};

  final ValueNotifier<AppearanceSettings> _settingsNotifier =
      ValueNotifier<AppearanceSettings>(const AppearanceSettings());

  AppearanceSettings get settings => _settings;

  ValueListenable<AppearanceSettings> get listenable => _settingsNotifier;

  Future<AppearanceSettings> load() {
    final existing = _loadFuture;
    if (existing != null) {
      return existing;
    }

    final future = _loadOnce();
    _loadFuture = future;
    return future;
  }

  Future<List<AppearanceFontOption>> loadUiFontChoices() async {
    final fontFamilies = await fontCatalog.uiFontFamilies();
    _rememberFontDisplayNames(fontFamilies);
    return <AppearanceFontOption>[
      const AppearanceFontOption.systemDefault(),
      ...fontFamilies.map(AppearanceFontOption.system),
    ];
  }

  Future<List<AppearanceFontOption>> loadCodeFontChoices() async {
    final fontFamilies = await fontCatalog.codeFontFamilies();
    _rememberFontDisplayNames(fontFamilies);
    return <AppearanceFontOption>[
      const AppearanceFontOption.bundledJetBrainsMono(),
      ...fontFamilies.map(AppearanceFontOption.system),
    ];
  }

  /// 返回系统字体在当前语言下的展示名称。
  String displayNameFor(AppearanceFontChoice choice) {
    final fontFamily = choice.fontFamily;
    if (!choice.isSystemFont || fontFamily == null) {
      return fontFamily ?? '';
    }
    return _fontDisplayNames[fontFamily.toLowerCase()] ?? fontFamily;
  }

  Future<bool> setThemeMode(ThemeMode mode) async {
    await load();
    if (_settings.themeMode == mode) {
      return true;
    }
    await _applySettings(_settings.copyWith(themeMode: mode));
    return true;
  }

  Future<bool> setUiFontChoice(AppearanceFontChoice choice) async {
    await load();
    if (_settings.uiFontChoice == choice) {
      return true;
    }
    final normalized = switch (choice.kind) {
      AppearanceFontChoiceKind.systemDefault => choice,
      AppearanceFontChoiceKind.system => await _tryResolveSystemChoice(choice),
      AppearanceFontChoiceKind.bundledJetBrainsMono => null,
    };
    if (normalized == null) {
      return false;
    }
    await _applySettings(_settings.copyWith(uiFontChoice: normalized));
    return true;
  }

  Future<bool> setCodeFontChoice(AppearanceFontChoice choice) async {
    await load();
    if (_settings.codeFontChoice == choice) {
      return true;
    }
    final normalized = switch (choice.kind) {
      AppearanceFontChoiceKind.bundledJetBrainsMono => choice,
      AppearanceFontChoiceKind.system => await _tryResolveSystemChoice(
        choice,
        requireMonospace: true,
      ),
      AppearanceFontChoiceKind.systemDefault => null,
    };
    if (normalized == null) {
      return false;
    }
    await _applySettings(_settings.copyWith(codeFontChoice: normalized));
    return true;
  }

  /// 更新界面基准字号；输入会按整数步进并限制在领域允许范围内。
  Future<bool> setUiFontSize(double value) async {
    await load();
    final normalized = _normalizeFontSize(
      value,
      min: minUiFontSize,
      max: maxUiFontSize,
    );
    if (normalized == null) {
      return false;
    }
    if (_settings.uiFontSize == normalized) {
      return true;
    }
    await _applySettings(_settings.copyWith(uiFontSize: normalized));
    return true;
  }

  /// 更新代码基准字号；输入会按整数步进并限制在领域允许范围内。
  Future<bool> setCodeFontSize(double value) async {
    await load();
    final normalized = _normalizeFontSize(
      value,
      min: minCodeFontSize,
      max: maxCodeFontSize,
    );
    if (normalized == null) {
      return false;
    }
    if (_settings.codeFontSize == normalized) {
      return true;
    }
    await _applySettings(_settings.copyWith(codeFontSize: normalized));
    return true;
  }

  Future<AppearanceSettings> _loadOnce() async {
    final stored = await store.load();
    final normalized = await _normalizeSettings(stored);
    _settings = normalized;
    _notify();
    return normalized;
  }

  Future<AppearanceSettings> _normalizeSettings(
    AppearanceSettings value,
  ) async {
    var normalized = value;

    final uiChoice = normalized.uiFontChoice;
    if (uiChoice.isSystemFont) {
      final resolved = await _resolveStoredSystemChoice(uiChoice);
      if (resolved == null) {
        normalized = normalized.copyWith(
          uiFontChoice: const AppearanceFontChoice.systemDefault(),
        );
      } else if (resolved != uiChoice) {
        normalized = normalized.copyWith(uiFontChoice: resolved);
      }
    }

    final codeChoice = normalized.codeFontChoice;
    if (codeChoice.isSystemFont) {
      final resolved = await _resolveStoredSystemChoice(
        codeChoice,
        requireMonospace: true,
      );
      if (resolved == null) {
        normalized = normalized.copyWith(
          codeFontChoice: const AppearanceFontChoice.bundledJetBrainsMono(),
        );
      } else if (resolved != codeChoice) {
        normalized = normalized.copyWith(codeFontChoice: resolved);
      }
    }

    if (normalized != value) {
      try {
        await store.save(normalized);
      } catch (error, stackTrace) {
        _log.warning(
          'Could not persist normalized appearance settings',
          error,
          stackTrace,
        );
      }
    }
    return normalized;
  }

  Future<void> _applySettings(AppearanceSettings value) async {
    _settings = value;
    try {
      await store.save(value);
    } catch (error, stackTrace) {
      _log.warning('Could not persist appearance settings', error, stackTrace);
    }
    _notify();
  }

  Future<AppearanceFontChoice?> _resolveSystemChoice(
    AppearanceFontChoice choice, {
    bool requireMonospace = false,
  }) async {
    final family = await fontCatalog.resolveFontFamily(choice.fontFamily!);
    if (family == null || (requireMonospace && !family.isMonospace)) {
      _log.warning('Could not resolve system font: ${choice.fontFamily}');
      return null;
    }
    _rememberFontDisplayNames(<SystemFontFamily>[family]);
    return AppearanceFontChoice.system(family.familyName);
  }

  Future<AppearanceFontChoice?> _tryResolveSystemChoice(
    AppearanceFontChoice choice, {
    bool requireMonospace = false,
  }) async {
    try {
      return await _resolveSystemChoice(
        choice,
        requireMonospace: requireMonospace,
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Could not query system font: ${choice.fontFamily}',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Future<AppearanceFontChoice?> _resolveStoredSystemChoice(
    AppearanceFontChoice choice, {
    bool requireMonospace = false,
  }) async {
    try {
      return await _resolveSystemChoice(
        choice,
        requireMonospace: requireMonospace,
      );
    } catch (error, stackTrace) {
      // 原生目录暂时不可用时保留用户设置，避免一次通道故障清空偏好。
      _log.warning(
        'Could not normalize stored system font: ${choice.fontFamily}',
        error,
        stackTrace,
      );
      return choice;
    }
  }

  void _rememberFontDisplayNames(Iterable<SystemFontFamily> families) {
    for (final family in families) {
      _fontDisplayNames[family.familyName.toLowerCase()] = family.displayName;
    }
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    _settingsNotifier.value = _settings;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _settingsNotifier.dispose();
    super.dispose();
  }
}

double? _normalizeFontSize(
  double value, {
  required double min,
  required double max,
}) {
  if (!value.isFinite) {
    return null;
  }
  return value.roundToDouble().clamp(min, max);
}
