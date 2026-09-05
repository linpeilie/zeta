/// 不同 Agent 协议中上下文窗口字段的兼容解析器。
abstract final class ContextWindowCodec {
  static const List<String> _keys = <String>[
    'modelContextWindow',
    'model_context_window',
    'contextWindow',
    'context_window',
    'maxContextTokens',
    'max_context_tokens',
    'totalContextTokens',
    'total_context_tokens',
    'maxInputTokens',
    'max_input_tokens',
  ];

  /// 按兼容键顺序读取第一个正整数；无可信值时返回 null。
  static int? positiveWindow(Map<String, Object?> map) {
    for (final key in _keys) {
      final value = positiveInt(map[key]);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  /// 将数值或数值字符串规范为正整数。
  static int? positiveInt(Object? value) {
    final parsed = switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text.trim()),
      _ => null,
    };
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
