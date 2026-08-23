import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 组合层注入的 appearance 切片 store；null = 切片路径未启用。
///
/// 与 Phase 2 的 resolver 模式同款：store 的生命周期归组合层（app session
/// 寿命），Riverpod 只读。默认 null，`MainApp` 在 `ProviderScope.overrides`
/// 里按 flag 注入实例。
final appearanceSettingsSliceStoreProvider =
    Provider<AppearanceSettingsSliceStore?>((ref) => null);

/// 组合层注入的 general 切片 store；null = 切片路径未启用。
final generalSettingsSliceStoreProvider = Provider<GeneralSettingsSliceStore?>(
  (ref) => null,
);

/// appearance 切片的 Riverpod 镜像。
///
/// 它**不拥有状态**：store 才是 source of truth，这里只是镜像 + 提供
/// selector 入口（与 Phase 2 的 `AgentConversationSliceNotifier` 同款）。
final appearanceSettingsSliceProvider =
    NotifierProvider<
      AppearanceSettingsSliceNotifier,
      AppearanceSettingsSliceState
    >(AppearanceSettingsSliceNotifier.new, name: 'appearanceSettingsSlice');

final class AppearanceSettingsSliceNotifier
    extends Notifier<AppearanceSettingsSliceState> {
  @override
  AppearanceSettingsSliceState build() {
    final store = ref.watch(appearanceSettingsSliceStoreProvider);
    if (store == null) {
      return const AppearanceSettingsSliceState();
    }
    final unsubscribe = store.subscribe(() => state = store.state);
    ref.onDispose(unsubscribe);
    return store.state;
  }
}

/// general 切片的 Riverpod 镜像。
final generalSettingsSliceProvider =
    NotifierProvider<GeneralSettingsSliceNotifier, GeneralSettingsSliceState>(
      GeneralSettingsSliceNotifier.new,
      name: 'generalSettingsSlice',
    );

final class GeneralSettingsSliceNotifier
    extends Notifier<GeneralSettingsSliceState> {
  @override
  GeneralSettingsSliceState build() {
    final store = ref.watch(generalSettingsSliceStoreProvider);
    if (store == null) {
      return const GeneralSettingsSliceState();
    }
    final unsubscribe = store.subscribe(() => state = store.state);
    ref.onDispose(unsubscribe);
    return store.state;
  }
}

// ---------------------------------------------------------------------------
// selector：主题构建与后续 pane 消费的最小投影
// ---------------------------------------------------------------------------

/// appearance 切片值 selector（主题构建入口）。
final appearanceSettingsSliceValueProvider = Provider<AppearanceSettingsSlice>(
  (ref) =>
      ref.watch(appearanceSettingsSliceProvider.select((state) => state.value)),
  name: 'appearanceSettingsSliceValue',
);

/// general 切片已应用设置 selector。
final generalSettingsSliceValueProvider = Provider<GeneralSettings>(
  (ref) =>
      ref.watch(generalSettingsSliceProvider.select((state) => state.settings)),
  name: 'generalSettingsSliceValue',
);
