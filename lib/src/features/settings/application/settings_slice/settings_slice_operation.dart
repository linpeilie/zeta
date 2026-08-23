/// settings 切片的命令作用域常量。
///
/// 只允许写死的字面量：`OperationId` 会进日志与指标，拼入运行期数据就等于泄露
/// （与 conversation 切片同一约定）。
abstract final class SettingsOperationScopes {
  static const String appearanceLoad = 'settings.appearance.load';
  static const String appearancePersist = 'settings.appearance.persist';
  static const String appearanceFontChoice = 'settings.appearance.fontChoice';
  static const String generalLoad = 'settings.general.load';
  static const String generalPersist = 'settings.general.persist';

  /// 全部作用域，供守卫与测试遍历。
  static const List<String> all = <String>[
    appearanceLoad,
    appearancePersist,
    appearanceFontChoice,
    generalLoad,
    generalPersist,
  ];
}

/// persist 失败的 typed 分类。
///
/// 只有分类没有文案：用户可见文字由 presentation 按 kind 取（G7），原始异常
/// 只由 effect runner 记入脱敏日志。
enum SettingsPersistFailureKind { persistence }
