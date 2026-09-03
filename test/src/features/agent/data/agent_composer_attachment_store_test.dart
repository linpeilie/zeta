import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/agent/data/agent_composer_attachment_store.dart';

void main() {
  group('AgentComposerAttachmentStore', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zeta-composer-attach-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('空输入仍写出文件', () async {
      final store = AgentComposerAttachmentStore(
        tempDirProvider: () => tempDir,
        clock: fixedClock(DateTime.utc(2026, 9, 3, 6, 40)),
      );
      final path = await store.stageClipboardImage(
        Uint8List(0),
        extension: 'png',
      );
      expect(File(path).existsSync(), isTrue);
      expect(File(path).lengthSync(), 0);
      expect(path, endsWith('.png'));
    });

    test('典型暂存写入字节并用时钟命名', () async {
      final instant = DateTime.utc(2026, 9, 3, 6, 40, 1);
      final store = AgentComposerAttachmentStore(
        tempDirProvider: () => tempDir,
        clock: fixedClock(instant),
      );
      final bytes = Uint8List.fromList(const <int>[137, 80, 78, 71]);
      final path = await store.stageClipboardImage(bytes, extension: 'PNG');
      expect(
        path,
        endsWith(
          '${Platform.pathSeparator}paste-${instant.microsecondsSinceEpoch}.png',
        ),
      );
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('discard 删除暂存文件并忽略外来路径', () async {
      final store = AgentComposerAttachmentStore(
        tempDirProvider: () => tempDir,
        clock: fixedClock(DateTime.utc(2026, 9, 3)),
      );
      final path = await store.stageClipboardImage(
        Uint8List.fromList(const <int>[1]),
        extension: 'png',
      );
      final outsider = File('${tempDir.path}${Platform.pathSeparator}keep.png')
        ..writeAsBytesSync(const <int>[2]);
      await store.discard(<String>[path, outsider.path]);
      expect(File(path).existsSync(), isFalse);
      expect(outsider.existsSync(), isTrue);
    });

    test('looksLikeImagePath 与顶层嗅探一致', () {
      final store = AgentComposerAttachmentStore(
        tempDirProvider: () => tempDir,
      );
      expect(store.looksLikeImagePath('/tmp/shot.bmp'), isTrue);
      expect(store.looksLikeImagePath('/tmp/shot'), isFalse);
    });
  });
}
