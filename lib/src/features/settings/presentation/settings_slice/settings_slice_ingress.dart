import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_mapping.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 迁移期 ingress：把旧 controller 的状态变化镜像进切片。
///
/// 第 1 批步骤 3–4 之间，**写入仍走旧 controller**（设置页未切换），而主题
/// 构建已经读切片——没有这座桥，用户改主题时切片不会跟着动。这与 Phase 2
/// 的「adapter 消费现有 store 的 region 更新」是同一模式；关批时随旧入口
/// 一起删除。
///
/// 镜像是幂等的：`loaded(...)` 在 reducer 里按值相等去重，echo 不产生发布。
final class SettingsSliceIngress {
  SettingsSliceIngress({
    required AppearanceSettingsController appearanceController,
    required GeneralSettingsController generalController,
    required this._appearanceSlice,
    required this._generalSlice,
  }) : _appearanceListenable = appearanceController.listenable,
       _generalListenable = generalController.listenable {
    _appearanceListenable.addListener(_onAppearanceChanged);
    _generalListenable.addListener(_onGeneralChanged);
  }

  final ValueListenable<AppearanceSettings> _appearanceListenable;
  final ValueListenable<GeneralSettings> _generalListenable;
  final AppearanceSettingsSliceStore _appearanceSlice;
  final GeneralSettingsSliceStore _generalSlice;

  void _onAppearanceChanged() {
    _appearanceSlice.loaded(
      appearanceSliceFromSettings(_appearanceListenable.value),
    );
  }

  void _onGeneralChanged() {
    _generalSlice.loaded(_generalListenable.value);
  }

  void dispose() {
    _appearanceListenable.removeListener(_onAppearanceChanged);
    _generalListenable.removeListener(_onGeneralChanged);
  }
}
