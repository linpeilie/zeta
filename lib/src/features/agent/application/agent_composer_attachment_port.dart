import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Composer 图片附件的暂存端口。
///
/// 实现放 data 层（含 `dart:io`）。路径属敏感信息（G7）：不落盘业务 JSON、
/// 不进日志与指标。
abstract interface class AgentComposerAttachmentPort {
  /// 把剪贴板图片字节暂存为临时文件，返回可供 Provider 消费的本地路径。
  Future<String> stageClipboardImage(
    Uint8List bytes, {
    required String extension,
  });

  /// 路径是否指向可支持的图片（扩展名嗅探）。
  bool looksLikeImagePath(String path);

  /// 清理本会话不再引用的暂存文件。未由本端口写出的路径必须忽略。
  Future<void> discard(List<String> paths);
}

/// 组合根必须覆盖：生产装 IO store，测试装内存 fake。
final agentComposerAttachmentPortProvider =
    Provider<AgentComposerAttachmentPort>(
      (ref) => throw StateError(
        'agentComposerAttachmentPortProvider must be overridden',
      ),
      name: 'agentComposerAttachmentPort',
    );

/// 按扩展名判断是否为 Composer 可附加的本地图片。
bool looksLikeAgentComposerImagePath(String path) {
  final lower = path.trim().toLowerCase();
  if (lower.isEmpty) {
    return false;
  }
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp');
}

/// 规范化扩展名；非法值回退 png，避免拼进路径。
String normalizeAgentComposerImageExtension(String extension) {
  var value = extension.trim().toLowerCase();
  if (value.startsWith('.')) {
    value = value.substring(1);
  }
  const allowed = <String>{'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
  if (!allowed.contains(value)) {
    return 'png';
  }
  return value;
}
