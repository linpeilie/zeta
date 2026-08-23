import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/appearance_font_option.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

export 'package:zeta/src/features/settings/domain/appearance_settings.dart'
    show ZetaThemeModePreference;

/// 字体目录的只读投影（source of truth 是 `SystemFontCatalogService`）。
///
/// 缓存四元组：source of truth = 系统字体目录服务；key = 目录槽位
/// （界面 / 代码）；invalidation = 显式 `AppearanceFontCatalogRequested`；
/// budget = 进程内，列表随系统目录规模有限。
@immutable
final class AppearanceFontCatalogProjection {
  const AppearanceFontCatalogProjection({
    this.uiOptions,
    this.codeOptions,
    this.displayNames = const <String, String>{},
  });

  /// 界面字体选项；null = 尚未加载。
  final List<AppearanceFontOption>? uiOptions;

  /// 代码字体选项；null = 尚未加载。
  final List<AppearanceFontOption>? codeOptions;

  /// `familyName.toLowerCase() → displayName`（选中字体的展示名查询）。
  final Map<String, String> displayNames;

  AppearanceFontCatalogProjection copyWith({
    Object? uiOptions = _unsetProjection,
    Object? codeOptions = _unsetProjection,
    Map<String, String>? displayNames,
  }) {
    return AppearanceFontCatalogProjection(
      uiOptions: uiOptions == _unsetProjection
          ? this.uiOptions
          : uiOptions as List<AppearanceFontOption>?,
      codeOptions: codeOptions == _unsetProjection
          ? this.codeOptions
          : codeOptions as List<AppearanceFontOption>?,
      displayNames: displayNames ?? this.displayNames,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppearanceFontCatalogProjection &&
        zetaListEquals(other.uiOptions, uiOptions) &&
        zetaListEquals(other.codeOptions, codeOptions) &&
        _mapEquals(other.displayNames, displayNames);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(uiOptions ?? const <Object?>[]),
    Object.hashAll(codeOptions ?? const <Object?>[]),
    Object.hashAllUnordered(
      displayNames.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

const Object _unsetProjection = Object();

/// 外观偏好的纯切片值，与 `AppearanceSettings` 字段一一对应。
///
/// 主题模式复用 domain 的 [ZetaThemeModePreference]（domain 已纯化），
/// 其余字段同样复用 domain 纯类型。
@immutable
final class AppearanceSettingsSlice {
  const AppearanceSettingsSlice({
    this.themeMode = ZetaThemeModePreference.system,
    this.uiFontChoice = const AppearanceFontChoice.systemDefault(),
    this.codeFontChoice = const AppearanceFontChoice.bundledJetBrainsMono(),
    this.uiFontSize = defaultUiFontSize,
    this.codeFontSize = defaultCodeFontSize,
  });

  final ZetaThemeModePreference themeMode;
  final AppearanceFontChoice uiFontChoice;
  final AppearanceFontChoice codeFontChoice;
  final double uiFontSize;
  final double codeFontSize;

  AppearanceSettingsSlice copyWith({
    ZetaThemeModePreference? themeMode,
    AppearanceFontChoice? uiFontChoice,
    AppearanceFontChoice? codeFontChoice,
    double? uiFontSize,
    double? codeFontSize,
  }) {
    return AppearanceSettingsSlice(
      themeMode: themeMode ?? this.themeMode,
      uiFontChoice: uiFontChoice ?? this.uiFontChoice,
      codeFontChoice: codeFontChoice ?? this.codeFontChoice,
      uiFontSize: uiFontSize ?? this.uiFontSize,
      codeFontSize: codeFontSize ?? this.codeFontSize,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettingsSlice &&
      other.themeMode == themeMode &&
      other.uiFontChoice == uiFontChoice &&
      other.codeFontChoice == codeFontChoice &&
      other.uiFontSize == uiFontSize &&
      other.codeFontSize == codeFontSize;

  @override
  int get hashCode => Object.hash(
    themeMode,
    uiFontChoice,
    codeFontChoice,
    uiFontSize,
    codeFontSize,
  );
}

/// appearance 切片的完整可渲染状态。
///
/// 只持有纯 Dart 值与在途操作身份（§7.3 application state），不新增业务事实。
@immutable
final class AppearanceSettingsSliceState {
  const AppearanceSettingsSliceState({
    this.value = const AppearanceSettingsSlice(),
    this.pendingUiFontChoiceOperationId,
    this.pendingCodeFontChoiceOperationId,
    this.catalog = const AppearanceFontCatalogProjection(),
  });

  final AppearanceSettingsSlice value;

  /// 在途「界面字体解析」的身份；新的选择覆盖它，旧解析结果按此判迟到。
  ///
  /// 界面 / 代码两个槽位独立追踪：现状串行队列会把两次快速选择都应用上，
  /// 单一 pending 会把第一次误判为迟到而丢弃。
  final OperationId? pendingUiFontChoiceOperationId;

  /// 在途「代码字体解析」的身份（必须解析为等宽系统字体）。
  final OperationId? pendingCodeFontChoiceOperationId;

  /// 字体目录投影（选项列表 + 展示名映射）。
  final AppearanceFontCatalogProjection catalog;

  AppearanceSettingsSliceState copyWith({
    AppearanceSettingsSlice? value,
    Object? pendingUiFontChoiceOperationId = _unset,
    Object? pendingCodeFontChoiceOperationId = _unset,
    AppearanceFontCatalogProjection? catalog,
  }) {
    return AppearanceSettingsSliceState(
      value: value ?? this.value,
      pendingUiFontChoiceOperationId: pendingUiFontChoiceOperationId == _unset
          ? this.pendingUiFontChoiceOperationId
          : pendingUiFontChoiceOperationId as OperationId?,
      pendingCodeFontChoiceOperationId:
          pendingCodeFontChoiceOperationId == _unset
          ? this.pendingCodeFontChoiceOperationId
          : pendingCodeFontChoiceOperationId as OperationId?,
      catalog: catalog ?? this.catalog,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettingsSliceState &&
      other.value == value &&
      other.pendingUiFontChoiceOperationId == pendingUiFontChoiceOperationId &&
      other.pendingCodeFontChoiceOperationId ==
          pendingCodeFontChoiceOperationId &&
      other.catalog == catalog;

  @override
  int get hashCode => Object.hash(
    value,
    pendingUiFontChoiceOperationId,
    pendingCodeFontChoiceOperationId,
    catalog,
  );
}

const Object _unset = Object();
