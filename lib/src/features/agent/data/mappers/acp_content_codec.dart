import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 标准 ACP content block 的编解码工具。
class AcpContentCodec {
  const AcpContentCodec._();

  /// 从 text content block 中读取文本；未知 block 返回 `null`。
  static String? textFromContent(Object? content) {
    if (content is String) {
      return content;
    }
    if (content is Map) {
      final map = content.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
      if (map['type'] == null || map['type']?.toString() == 'text') {
        return map['text']?.toString();
      }
    }
    return null;
  }

  /// 将工具调用 content 列表转换为紧凑可读文本。
  static String? toolContentText(Object? content) {
    if (content == null) {
      return null;
    }
    if (content is String) {
      return content;
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final map = item.map(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
        final type = map['type']?.toString();
        if (type == 'content') {
          final nested = textFromContent(map['content']);
          if (nested != null) {
            if (buffer.isNotEmpty) {
              buffer.writeln();
            }
            buffer.write(nested);
          }
        } else if (type == 'diff') {
          final path = map['path']?.toString() ?? 'file';
          if (buffer.isNotEmpty) {
            buffer.writeln();
          }
          buffer.write('diff: $path');
        }
      }
      final text = buffer.toString();
      return text.isEmpty ? null : text;
    }
    return content.toString();
  }

  /// 将中立用户输入编码为 ACP prompt blocks。
  ///
  /// 标准 ACP 图片 block 需要实际 MIME/base64 数据；当前 Grok 仅支持路径提示，
  /// 因此由 [encodeLocalImagesAsPathText] 显式开启兼容降级，不能冒充图片能力。
  static List<Map<String, Object?>> buildPromptBlocks({
    String? message,
    List<AgentUserInput>? inputs,
    required AgentContext context,
    bool encodeLocalImagesAsPathText = false,
  }) {
    final blocks = <Map<String, Object?>>[];
    final resolved = <AgentUserInput>[
      if (inputs != null && inputs.isNotEmpty)
        ...inputs
      else if ((message?.trim().isNotEmpty ?? false))
        AgentUserInput.text(message!.trim()),
    ];
    if (resolved.isEmpty) {
      throw ArgumentError('prompt requires message or inputs');
    }

    for (final input in resolved) {
      switch (input) {
        case AgentTextUserInput(:final text):
          blocks.add(<String, Object?>{'type': 'text', 'text': text});
        case AgentLocalImageUserInput(:final path):
          if (!encodeLocalImagesAsPathText) {
            throw UnsupportedError(
              'Local images require a provider-specific ACP image encoder',
            );
          }
          blocks.add(<String, Object?>{
            'type': 'text',
            'text': '[local image: $path]',
          });
        case AgentMentionUserInput(:final name, :final path):
          blocks.add(_resourceLink(name: name, path: path));
      }
    }

    final filePath = context.filePath?.trim();
    if (filePath != null && filePath.isNotEmpty) {
      blocks.add(
        _resourceLink(
          name: filePath.split(RegExp(r'[\\/]')).last,
          path: filePath,
        ),
      );
    }
    return blocks;
  }

  static Map<String, Object?> _resourceLink({
    required String name,
    required String path,
  }) {
    return <String, Object?>{
      'type': 'resource_link',
      'uri': path.startsWith('file:') ? path : 'file:///$path',
      'name': name,
    };
  }
}
