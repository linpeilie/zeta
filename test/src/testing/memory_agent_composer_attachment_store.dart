import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta/src/features/agent/application/agent_composer_attachment_port.dart';

/// 测试用内存暂存：不碰本机文件系统。
final class MemoryAgentComposerAttachmentStore
    implements AgentComposerAttachmentPort {
  final Map<String, Uint8List> staged = <String, Uint8List>{};
  final List<String> discarded = <String>[];
  int _sequence = 0;

  @override
  Future<String> stageClipboardImage(
    Uint8List bytes, {
    required String extension,
  }) async {
    final ext = normalizeAgentComposerImageExtension(extension);
    final path = 'memory://paste-${_sequence++}.$ext';
    staged[path] = Uint8List.fromList(bytes);
    return path;
  }

  @override
  bool looksLikeImagePath(String path) => looksLikeAgentComposerImagePath(path);

  @override
  Future<void> discard(List<String> paths) async {
    for (final path in paths) {
      if (staged.remove(path) == null) {
        continue;
      }
      discarded.add(path);
    }
  }
}

/// widget / 组合测试覆盖附件端口。
Override memoryAgentComposerAttachmentOverride([
  MemoryAgentComposerAttachmentStore? store,
]) {
  return agentComposerAttachmentPortProvider.overrideWithValue(
    store ?? MemoryAgentComposerAttachmentStore(),
  );
}
