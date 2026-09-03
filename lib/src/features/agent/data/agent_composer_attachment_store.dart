import 'dart:io';
import 'dart:typed_data';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/agent/application/agent_composer_attachment_port.dart';

/// 把剪贴板图片写到本机临时目录。只删除自己写出的路径。
final class AgentComposerAttachmentStore
    implements AgentComposerAttachmentPort {
  AgentComposerAttachmentStore({
    Directory Function()? tempDirProvider,
    this._clock = systemClock,
  }) : _tempDirProvider = tempDirProvider ?? _defaultTempDir;

  final Directory Function() _tempDirProvider;
  final Clock _clock;
  final Set<String> _stagedPaths = <String>{};

  @override
  Future<String> stageClipboardImage(
    Uint8List bytes, {
    required String extension,
  }) async {
    final root = _tempDirProvider();
    await root.create(recursive: true);
    final ext = normalizeAgentComposerImageExtension(extension);
    final file = File(
      '${root.path}${Platform.pathSeparator}'
      'paste-${_clock().microsecondsSinceEpoch}.$ext',
    );
    await file.writeAsBytes(bytes, flush: true);
    _stagedPaths.add(file.path);
    return file.path;
  }

  @override
  bool looksLikeImagePath(String path) => looksLikeAgentComposerImagePath(path);

  @override
  Future<void> discard(List<String> paths) async {
    for (final path in paths) {
      if (!_stagedPaths.remove(path)) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException {
        // 临时文件可能已被系统清掉；忽略。
      }
    }
  }
}

Directory _defaultTempDir() => Directory(
  '${Directory.systemTemp.path}${Platform.pathSeparator}zeta-agent-images',
);
