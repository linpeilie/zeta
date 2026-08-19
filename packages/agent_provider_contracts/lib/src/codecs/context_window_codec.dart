/// Compatible parser for context-window fields across agent protocols.
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

  static int? positiveWindow(Map<String, Object?> map) {
    for (final key in _keys) {
      final value = positiveInt(map[key]);
      if (value != null) return value;
    }
    return null;
  }

  static int? positiveInt(Object? value) {
    final parsed = switch (value) {
      final int number => number,
      final num number => number.toInt(),
      final String text => int.tryParse(text.trim()),
      _ => null,
    };
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
