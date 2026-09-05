import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/appearance_font_option.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_mapping.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings_repository.dart';
import 'package:zeta/src/features/settings/domain/system_font_catalog_service.dart';

final _log = zetaLoggerFor('zeta.settings.appearance');

/// 外观仓库。组合根必须覆盖；缺失即为接线错误。
final appearanceSettingsRepositoryProvider =
    Provider<AppearanceSettingsRepository>(
      (ref) =>
          throw StateError('Appearance settings repository is not installed'),
      name: 'appearanceSettingsRepository',
    );

/// 系统字体目录。组合根必须覆盖。
final appearanceFontCatalogProvider = Provider<SystemFontCatalogService>(
  (ref) => throw StateError('Appearance font catalog is not installed'),
  name: 'appearanceFontCatalog',
);

/// 启动阶段已读入的外观偏好，供第一帧使用，避免先按默认 system 再跳变。
final initialAppearanceSettingsProvider = Provider<AppearanceSettings>(
  (ref) => const AppearanceSettings(),
  name: 'initialAppearanceSettings',
);

/// 外观运行态的唯一 owner。
final appearanceSettingsProvider =
    NotifierProvider<AppearanceSettingsNotifier, AppearanceSettingsSliceState>(
      AppearanceSettingsNotifier.new,
      name: 'appearanceSettings',
    );

/// 主题构建与设置页消费的最小投影。
final appearanceSettingsValueProvider = Provider<AppearanceSettingsSlice>(
  (ref) => ref.watch(appearanceSettingsProvider.select((state) => state.value)),
  name: 'appearanceSettingsValue',
);

/// 外观设置的 Riverpod 状态层。
///
/// 乐观更新 [state]，再把整份快照交给 [AppearanceSettingsRepository.save]。
/// 失败只记脱敏日志、不回滚（与原切片语义 A 一致）。repository 本身不缓存。
final class AppearanceSettingsNotifier
    extends Notifier<AppearanceSettingsSliceState> {
  Future<void> _writes = Future<void>.value();
  Future<void> _hydrate = Future<void>.value();
  bool _hydrateStarted = false;
  int _fontChoiceSequence = 0;

  @override
  AppearanceSettingsSliceState build() {
    final initial = ref.watch(initialAppearanceSettingsProvider);
    if (!_hydrateStarted) {
      _hydrateStarted = true;
      _hydrate = _loadFromRepository();
    }
    return AppearanceSettingsSliceState(
      value: appearanceSliceFromSettings(initial),
    );
  }

  AppearanceSettingsRepository get _repository =>
      ref.read(appearanceSettingsRepositoryProvider);

  SystemFontCatalogService get _fontCatalog =>
      ref.read(appearanceFontCatalogProvider);

  /// 选择主题模式。
  Future<void> setThemeMode(ZetaThemeModePreference mode) async {
    if (!ref.mounted || state.value.themeMode == mode) {
      return;
    }
    state = state.copyWith(value: state.value.copyWith(themeMode: mode));
    await _hydrate;
    if (!ref.mounted) {
      return;
    }
    await _persist();
  }

  /// 调整界面字号。
  Future<void> setUiFontSize(double value) async {
    if (!ref.mounted) {
      return;
    }
    final normalized = normalizeSettingsFontSize(
      value,
      min: minUiFontSize,
      max: maxUiFontSize,
    );
    if (normalized == null || normalized == state.value.uiFontSize) {
      return;
    }
    state = state.copyWith(value: state.value.copyWith(uiFontSize: normalized));
    await _hydrate;
    if (!ref.mounted) {
      return;
    }
    await _persist();
  }

  /// 调整代码字号。
  Future<void> setCodeFontSize(double value) async {
    if (!ref.mounted) {
      return;
    }
    final normalized = normalizeSettingsFontSize(
      value,
      min: minCodeFontSize,
      max: maxCodeFontSize,
    );
    if (normalized == null || normalized == state.value.codeFontSize) {
      return;
    }
    state = state.copyWith(
      value: state.value.copyWith(codeFontSize: normalized),
    );
    await _hydrate;
    if (!ref.mounted) {
      return;
    }
    await _persist();
  }

  /// 选择界面字体。解析失败不应用。
  Future<bool> setUiFontChoice(AppearanceFontChoice choice) {
    return _setFontChoice(choice, forCodeFont: false);
  }

  /// 选择代码字体。解析失败不应用。
  Future<bool> setCodeFontChoice(AppearanceFontChoice choice) {
    return _setFontChoice(choice, forCodeFont: true);
  }

  /// 确保字体目录已加载；已有缓存则直接返回。
  Future<List<AppearanceFontOption>> ensureFontCatalog({
    required bool forCodeFont,
  }) async {
    final loaded = forCodeFont
        ? state.catalog.codeOptions
        : state.catalog.uiOptions;
    if (loaded != null) {
      return loaded;
    }
    try {
      final families = forCodeFont
          ? await _fontCatalog.codeFontFamilies()
          : await _fontCatalog.uiFontFamilies();
      if (!ref.mounted) {
        return const <AppearanceFontOption>[];
      }
      final options = <AppearanceFontOption>[
        if (forCodeFont)
          const AppearanceFontOption.bundledJetBrainsMono()
        else
          const AppearanceFontOption.systemDefault(),
        ...families.map(AppearanceFontOption.system),
      ];
      final names = <String, String>{
        ...state.catalog.displayNames,
        for (final family in families)
          family.familyName.toLowerCase(): family.displayName,
      };
      state = state.copyWith(
        catalog: forCodeFont
            ? state.catalog.copyWith(codeOptions: options, displayNames: names)
            : state.catalog.copyWith(uiOptions: options, displayNames: names),
      );
      return options;
    } catch (error, stackTrace) {
      _log.w(
        'Could not load system font catalog',
        error: error,
        stackTrace: stackTrace,
      );
      if (!ref.mounted) {
        return const <AppearanceFontOption>[];
      }
      final empty = const <AppearanceFontOption>[];
      state = state.copyWith(
        catalog: forCodeFont
            ? state.catalog.copyWith(codeOptions: empty)
            : state.catalog.copyWith(uiOptions: empty),
      );
      return empty;
    }
  }

  /// 选中字体的展示名。
  String displayNameFor(AppearanceFontChoice choice) {
    final family = choice.fontFamily;
    if (family == null) {
      return '';
    }
    return state.catalog.displayNames[family.toLowerCase()] ?? family;
  }

  Future<bool> _setFontChoice(
    AppearanceFontChoice choice, {
    required bool forCodeFont,
  }) async {
    if (!ref.mounted) {
      return false;
    }
    final current = forCodeFont
        ? state.value.codeFontChoice
        : state.value.uiFontChoice;
    if (current == choice) {
      return true;
    }
    _fontChoiceSequence += 1;
    final operationId = OperationId(
      scope: SettingsOperationScopes.appearanceFontChoice,
      sequence: _fontChoiceSequence,
    );
    state = forCodeFont
        ? state.copyWith(pendingCodeFontChoiceOperationId: operationId)
        : state.copyWith(pendingUiFontChoiceOperationId: operationId);
    final resolved = await _resolveChoice(choice, forCodeFont: forCodeFont);
    if (!ref.mounted) {
      return false;
    }
    final pending = forCodeFont
        ? state.pendingCodeFontChoiceOperationId
        : state.pendingUiFontChoiceOperationId;
    if (pending != operationId) {
      return false;
    }
    if (resolved == null) {
      state = forCodeFont
          ? state.copyWith(pendingCodeFontChoiceOperationId: null)
          : state.copyWith(pendingUiFontChoiceOperationId: null);
      return false;
    }
    final nextValue = forCodeFont
        ? state.value.copyWith(codeFontChoice: resolved)
        : state.value.copyWith(uiFontChoice: resolved);
    state = forCodeFont
        ? state.copyWith(
            value: nextValue,
            pendingCodeFontChoiceOperationId: null,
          )
        : state.copyWith(
            value: nextValue,
            pendingUiFontChoiceOperationId: null,
          );
    await _hydrate;
    if (!ref.mounted) {
      return false;
    }
    await _persist();
    return true;
  }

  Future<void> _loadFromRepository() async {
    final seed = appearanceSliceFromSettings(
      ref.read(initialAppearanceSettingsProvider),
    );
    try {
      final stored = await _repository.load();
      final normalized = await _normalizeSettings(stored);
      if (!ref.mounted) {
        return;
      }
      final loaded = appearanceSliceFromSettings(normalized);
      final merged = _mergeLoaded(
        seed: seed,
        loaded: loaded,
        current: state.value,
      );
      if (merged != state.value) {
        state = state.copyWith(value: merged);
      }
    } catch (error, stackTrace) {
      _log.w(
        'Could not load appearance settings',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _persist() {
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (!ref.mounted) {
        return;
      }
      final snapshot = appearanceSettingsFromSlice(state.value);
      try {
        await _repository.save(snapshot);
      } catch (error, stackTrace) {
        _log.w(
          'Could not persist appearance settings',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
    return _writes;
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
        await _repository.save(normalized);
      } catch (error, stackTrace) {
        _log.w(
          'Could not persist normalized appearance settings',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return normalized;
  }

  Future<AppearanceFontChoice?> _resolveChoice(
    AppearanceFontChoice choice, {
    required bool forCodeFont,
  }) async {
    switch (choice.kind) {
      case AppearanceFontChoiceKind.systemDefault:
        return forCodeFont ? null : choice;
      case AppearanceFontChoiceKind.bundledJetBrainsMono:
        return forCodeFont ? choice : null;
      case AppearanceFontChoiceKind.system:
        try {
          return await _resolveSystemChoice(
            choice,
            requireMonospace: forCodeFont,
          );
        } catch (error, stackTrace) {
          _log.w(
            'Could not query system font: ${choice.fontFamily}',
            error: error,
            stackTrace: stackTrace,
          );
          return null;
        }
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
      _log.w(
        'Could not normalize stored system font: ${choice.fontFamily}',
        error: error,
        stackTrace: stackTrace,
      );
      return choice;
    }
  }

  Future<AppearanceFontChoice?> _resolveSystemChoice(
    AppearanceFontChoice choice, {
    required bool requireMonospace,
  }) async {
    final family = await _fontCatalog.resolveFontFamily(choice.fontFamily!);
    if (family == null || (requireMonospace && !family.isMonospace)) {
      _log.w('Could not resolve system font: ${choice.fontFamily}');
      return null;
    }
    return AppearanceFontChoice.system(family.familyName);
  }
}

/// 启动快照 [seed] 上，用户已改的字段保留，其余用磁盘 [loaded]。
AppearanceSettingsSlice _mergeLoaded({
  required AppearanceSettingsSlice seed,
  required AppearanceSettingsSlice loaded,
  required AppearanceSettingsSlice current,
}) {
  return AppearanceSettingsSlice(
    themeMode: current.themeMode != seed.themeMode
        ? current.themeMode
        : loaded.themeMode,
    uiFontChoice: current.uiFontChoice != seed.uiFontChoice
        ? current.uiFontChoice
        : loaded.uiFontChoice,
    codeFontChoice: current.codeFontChoice != seed.codeFontChoice
        ? current.codeFontChoice
        : loaded.codeFontChoice,
    uiFontSize: current.uiFontSize != seed.uiFontSize
        ? current.uiFontSize
        : loaded.uiFontSize,
    codeFontSize: current.codeFontSize != seed.codeFontSize
        ? current.codeFontSize
        : loaded.codeFontSize,
  );
}
