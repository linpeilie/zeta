import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

final _log = loggerFor('zeta.settings.appearance_controller');

/// 全局外观设置控制器。
///
/// 负责外观偏好加载、持久化以及系统字体按需加载。
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

  Future<List<AppearanceFontChoice>> loadUiFontChoices() async {
    final fontFamilies = await fontCatalog.uiFontFamilies();
    return <AppearanceFontChoice>[
      const AppearanceFontChoice.systemDefault(),
      ...fontFamilies.map(AppearanceFontChoice.system),
    ];
  }

  Future<List<AppearanceFontChoice>> loadCodeFontChoices() async {
    final fontFamilies = await fontCatalog.codeFontFamilies();
    return <AppearanceFontChoice>[
      const AppearanceFontChoice.bundledJetBrainsMono(),
      ...fontFamilies.map(AppearanceFontChoice.system),
    ];
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
      AppearanceFontChoiceKind.system =>
        await _tryLoadSystemFont(choice.fontFamily!) ? choice : null,
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
      AppearanceFontChoiceKind.system =>
        await _tryLoadSystemFont(choice.fontFamily!) ? choice : null,
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
    if (uiChoice.isSystemFont &&
        !await _tryLoadSystemFont(uiChoice.fontFamily!)) {
      normalized = normalized.copyWith(
        uiFontChoice: const AppearanceFontChoice.systemDefault(),
      );
    }

    final codeChoice = normalized.codeFontChoice;
    if (codeChoice.isSystemFont &&
        !await _tryLoadSystemFont(codeChoice.fontFamily!)) {
      normalized = normalized.copyWith(
        codeFontChoice: const AppearanceFontChoice.bundledJetBrainsMono(),
      );
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

  Future<bool> _tryLoadSystemFont(String fontFamily) async {
    final loaded = await fontCatalog.ensureFontLoaded(fontFamily);
    if (!loaded) {
      _log.warning('Could not load system font: $fontFamily');
    }
    return loaded;
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
