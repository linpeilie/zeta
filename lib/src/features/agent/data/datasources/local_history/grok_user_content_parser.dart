/// Grok 用户消息中从文本占位符恢复出的结构化内容。
class GrokParsedUserContent {
  const GrokParsedUserContent({
    required this.text,
    required this.localImagePaths,
  });

  /// 移除内部图片占位符后的可见文本。
  final String text;

  /// `[local image: ...]` 占位符携带的本地图片路径。
  final List<String> localImagePaths;
}

final RegExp _localImageMarker = RegExp(
  r'\[local image:\s*(.+?)\]',
  caseSensitive: false,
);

/// 把 Grok ACP 写入历史的本地图片占位符恢复为结构化附件。
GrokParsedUserContent parseGrokUserContent(String value) {
  final paths = <String>[];
  final seenPaths = <String>{};
  final text = value.replaceAllMapped(_localImageMarker, (match) {
    final path = match.group(1)?.trim();
    if (path != null && path.isNotEmpty && seenPaths.add(path)) {
      paths.add(path);
    }
    return '';
  }).trim();

  return GrokParsedUserContent(
    text: text,
    localImagePaths: List<String>.unmodifiable(paths),
  );
}
