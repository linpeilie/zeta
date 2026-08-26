import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

/// 外观设置的持久化端口。
///
/// 只负责整份 [AppearanceSettings] 的读、写，不缓存、不认识 Flutter 主题类型。
/// 每次 [load] / [save] 都打到底层 `StorageService`；进程内当前值由
/// application 的 Notifier 持有。字段级更新走 Notifier 的整份 [save]，
/// 不要在仓库上做读改写。
abstract interface class AppearanceSettingsRepository {
  /// 读取 `appearance.json`；缺失或损坏时由实现按宽容语义给出默认值。
  Future<AppearanceSettings> load();

  /// 原子替换整份外观文档。
  Future<void> save(AppearanceSettings settings);
}
