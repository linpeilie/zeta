import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_state.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_store.dart';

/// 由 MainApp 根组合覆盖；没有安全的伪实现，漏接线直接失败。
final desktopAttentionSliceStoreProvider = Provider<DesktopAttentionSliceStore>(
  (ref) => throw StateError(
    'desktopAttentionSliceStoreProvider must be overridden by MainApp',
  ),
  name: 'desktopAttentionSliceStore',
);

final desktopAttentionSliceProvider =
    NotifierProvider<DesktopAttentionSliceNotifier, DesktopAttentionSliceState>(
      DesktopAttentionSliceNotifier.new,
      name: 'desktopAttentionSlice',
    );

final class DesktopAttentionSliceNotifier
    extends Notifier<DesktopAttentionSliceState> {
  @override
  DesktopAttentionSliceState build() {
    final store = ref.watch(desktopAttentionSliceStoreProvider);
    void listener() => state = store.state;
    store.addListener(listener);
    ref.onDispose(() => store.removeListener(listener));
    return store.state;
  }
}

final desktopAttentionUnreadCountProvider = Provider<int>(
  (ref) => ref.watch(
    desktopAttentionSliceProvider.select((state) => state.unreadCount),
  ),
  name: 'desktopAttentionUnreadCount',
);
