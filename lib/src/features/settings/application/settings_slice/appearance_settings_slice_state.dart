import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

export 'package:zeta/src/features/settings/domain/appearance_settings.dart'
    show ZetaThemeModePreference;

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
  });

  final AppearanceSettingsSlice value;

  /// 在途「界面字体解析」的身份；新的选择覆盖它，旧解析结果按此判迟到。
  ///
  /// 界面 / 代码两个槽位独立追踪：现状串行队列会把两次快速选择都应用上，
  /// 单一 pending 会把第一次误判为迟到而丢弃。
  final OperationId? pendingUiFontChoiceOperationId;

  /// 在途「代码字体解析」的身份（必须解析为等宽系统字体）。
  final OperationId? pendingCodeFontChoiceOperationId;

  AppearanceSettingsSliceState copyWith({
    AppearanceSettingsSlice? value,
    Object? pendingUiFontChoiceOperationId = _unset,
    Object? pendingCodeFontChoiceOperationId = _unset,
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
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettingsSliceState &&
      other.value == value &&
      other.pendingUiFontChoiceOperationId == pendingUiFontChoiceOperationId &&
      other.pendingCodeFontChoiceOperationId ==
          pendingCodeFontChoiceOperationId;

  @override
  int get hashCode => Object.hash(
    value,
    pendingUiFontChoiceOperationId,
    pendingCodeFontChoiceOperationId,
  );
}

const Object _unset = Object();
