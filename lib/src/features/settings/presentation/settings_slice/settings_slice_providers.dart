import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_store.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 组合层注入的 general 切片 store；缺失时 fail closed。
final generalSettingsSliceStoreProvider = Provider<GeneralSettingsSliceStore>(
  (ref) => throw StateError('General settings slice is not installed'),
);

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
    final unsubscribe = store.subscribe(() => state = store.state);
    ref.onDispose(unsubscribe);
    return store.state;
  }
}

/// general 切片已应用设置 selector。
final generalSettingsSliceValueProvider = Provider<GeneralSettings>(
  (ref) =>
      ref.watch(generalSettingsSliceProvider.select((state) => state.settings)),
  name: 'generalSettingsSliceValue',
);
