import 'dart:math';

/// 指标标签值。
///
/// **隐私边界在类型上，不在正则上。** 早期实现让标签直接收 `String`，只用形态
/// 正则过滤——但 `secret.md`、`AliceProject`、`customer-name` 都是合法形态，
/// 而 provider ID 之类的值是从 `~/.zeta` 的 JSON 自由解码来的。形态校验只能
/// 判断"长什么样"，判断不了"从哪来"。
///
/// 因此标签只能由三个入口构造，按可信度从高到低：
///
/// | 入口 | 适用 | 保证 |
/// | --- | --- | --- |
/// | [ZetaMetricLabel.constant] | 源码里的字面量 | 编译期就在代码里，架构守卫强制实参为字面量 |
/// | [ZetaMetricLabel.declaredIdentifier] | 声明期常量经运行期传递（插件 ID、provider 名） | 形态不合法时**自动降级为 hash**，不会原样输出 |
/// | [ZetaMetricLabel.hashed] | 任何用户/配置来源的值 | 会话内不可逆短 hash，跨进程不可关联 |
///
/// 三个入口的产物都满足 [isValidLiteral] 的形态，可以安全地进日志与指标。
final class ZetaMetricLabel {
  /// 源码字面量标签。
  ///
  /// 只允许传字符串字面量；架构守卫会检查这一点。传运行期变量请改用
  /// [declaredIdentifier] 或 [hashed]。
  const ZetaMetricLabel.constant(this.value);

  const ZetaMetricLabel._(this.value);

  /// 声明期常量经由运行期字符串传递到这里（插件 ID、Riverpod provider 名）。
  ///
  /// 形态合法就原样保留；否则退化成 [hashed]——即使将来有人把配置里的值接到
  /// 这个入口上，也只会得到一串 hash，而不是可读内容。
  factory ZetaMetricLabel.declaredIdentifier(String value) {
    if (!isValidLiteral(value)) {
      return ZetaMetricLabel.hashed(value);
    }
    return ZetaMetricLabel._(value);
  }

  /// 会话内不可逆短 hash。
  ///
  /// 每个进程使用一次性随机盐：同一进程内同一取值稳定（可做聚合），跨进程无法
  /// 关联，也无法从 hash 反推原文。空串同样会被 hash，不做特例。
  factory ZetaMetricLabel.hashed(String value) {
    return ZetaMetricLabel._('h.${_shortHash(value)}');
  }

  /// 标签文本；已经是可安全外发的形态。
  final String value;

  /// 合法字面量形态：字母开头的短标识符。
  static bool isValidLiteral(String value) => _literalPattern.hasMatch(value);

  static final RegExp _literalPattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_.\-]{0,31}$',
  );

  /// 进程级随机盐，进程退出即失效。
  static final int _sessionSalt = Random.secure().nextInt(1 << 32);

  /// FNV-1a 64 位，取低 32 位输出 8 位十六进制。
  ///
  /// 截断本身就是不可逆的；盐只是防止跨会话关联，不承担保密职责。
  static String _shortHash(String value) {
    var hash = 0xcbf29ce484222325 ^ _sessionSalt;
    for (final unit in value.codeUnits) {
      hash = (hash ^ unit) * 0x100000001b3;
      hash &= 0xFFFFFFFFFFFFFFFF;
    }
    final low = hash & 0xFFFFFFFF;
    return low.toRadixString(16).padLeft(8, '0');
  }

  @override
  bool operator ==(Object other) =>
      other is ZetaMetricLabel && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
