import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/application/settings_slice/settings_slice_operation.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// general 切片的完整可渲染状态。
///
/// `settings` 直接复用 domain 的 [GeneralSettings]（纯 Dart 值对象）；
/// 其余是 §7.3 允许的 application state（在途身份 / 在途值 / 失败分类），
/// 不新增业务事实。
@immutable
final class GeneralSettingsSliceState {
  const GeneralSettingsSliceState({
    this.settings = const GeneralSettings(),
    this.pendingOperationId,
    this.pendingValue,
    this.lastPersistFailure,
  });

  /// 已应用的设置值（persist 成功才更新——现状语义 B）。
  final GeneralSettings settings;

  /// 在途 persist 的身份；新命令覆盖它，旧结果按此判迟到。
  final OperationId? pendingOperationId;

  /// 在途提交的完整值。
  ///
  /// **串行链的基线**：后续修改基于它 `copyWith`，等价于现有 controller 的
  /// 串行队列——否则 persist-first 下第二次快速修改会基于未应用旧值计算，
  /// 丢掉第一次的改动。
  final GeneralSettings? pendingValue;

  /// 最近一次 persist 失败的 typed 分类；presentation 弹 toast 后用
  /// `GeneralSettingsFailureAcknowledged` 清除（现状只有语言切换把失败
  /// 暴露给 UI，这里给全部命令同一种回执通道，展示与否由 presentation 决定）。
  final SettingsPersistFailureKind? lastPersistFailure;

  GeneralSettingsSliceState copyWith({
    GeneralSettings? settings,
    Object? pendingOperationId = _unset,
    Object? pendingValue = _unset,
    Object? lastPersistFailure = _unset,
  }) {
    return GeneralSettingsSliceState(
      settings: settings ?? this.settings,
      pendingOperationId: pendingOperationId == _unset
          ? this.pendingOperationId
          : pendingOperationId as OperationId?,
      pendingValue: pendingValue == _unset
          ? this.pendingValue
          : pendingValue as GeneralSettings?,
      lastPersistFailure: lastPersistFailure == _unset
          ? this.lastPersistFailure
          : lastPersistFailure as SettingsPersistFailureKind?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GeneralSettingsSliceState &&
      other.settings == settings &&
      other.pendingOperationId == pendingOperationId &&
      other.pendingValue == pendingValue &&
      other.lastPersistFailure == lastPersistFailure;

  @override
  int get hashCode => Object.hash(
    settings,
    pendingOperationId,
    pendingValue,
    lastPersistFailure,
  );
}

const Object _unset = Object();
