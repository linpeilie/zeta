import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_composer_attachment_port.dart';

import '../../../testing/memory_agent_composer_attachment_store.dart';

void main() {
  group('looksLikeAgentComposerImagePath', () {
    test('空路径不是图片', () {
      expect(looksLikeAgentComposerImagePath(''), isFalse);
      expect(looksLikeAgentComposerImagePath('   '), isFalse);
    });

    test('常见扩展名命中，大小写不敏感', () {
      expect(looksLikeAgentComposerImagePath(r'D:\tmp\a.PNG'), isTrue);
      expect(looksLikeAgentComposerImagePath('/tmp/b.jpeg'), isTrue);
      expect(looksLikeAgentComposerImagePath('c.webp'), isTrue);
    });

    test('非图片扩展名淘汰', () {
      expect(looksLikeAgentComposerImagePath('/tmp/notes.txt'), isFalse);
      expect(looksLikeAgentComposerImagePath('/tmp/photo.png.bak'), isFalse);
    });
  });

  group('normalizeAgentComposerImageExtension', () {
    test('空值与非法值回退 png', () {
      expect(normalizeAgentComposerImageExtension(''), 'png');
      expect(normalizeAgentComposerImageExtension('../exe'), 'png');
      expect(normalizeAgentComposerImageExtension('png.exe'), 'png');
    });

    test('去掉前导点并转小写', () {
      expect(normalizeAgentComposerImageExtension('.PNG'), 'png');
      expect(normalizeAgentComposerImageExtension('JPEG'), 'jpeg');
    });
  });

  group('MemoryAgentComposerAttachmentStore', () {
    test('空字节也可暂存；非法扩展名回退 png', () async {
      final store = MemoryAgentComposerAttachmentStore();
      final path = await store.stageClipboardImage(
        Uint8List(0),
        extension: '../exe',
      );
      expect(path, 'memory://paste-0.png');
      expect(store.staged[path], isEmpty);
    });

    test('典型暂存保留字节并递增路径', () async {
      final store = MemoryAgentComposerAttachmentStore();
      final first = await store.stageClipboardImage(
        Uint8List.fromList(const <int>[1, 2]),
        extension: 'jpg',
      );
      final second = await store.stageClipboardImage(
        Uint8List.fromList(const <int>[3]),
        extension: '.JPEG',
      );
      expect(first, 'memory://paste-0.jpg');
      expect(second, 'memory://paste-1.jpeg');
      expect(store.staged[first], <int>[1, 2]);
    });

    test('discard 只清理自己写出的路径', () async {
      final store = MemoryAgentComposerAttachmentStore();
      final path = await store.stageClipboardImage(
        Uint8List.fromList(const <int>[9]),
        extension: 'png',
      );
      await store.discard(<String>[path, '/not-staged.png']);
      expect(store.staged, isEmpty);
      expect(store.discarded, <String>[path]);
    });

    test('looksLikeImagePath 委托顶层嗅探', () {
      final store = MemoryAgentComposerAttachmentStore();
      expect(store.looksLikeImagePath(r'C:\tmp\a.gif'), isTrue);
      expect(store.looksLikeImagePath('/tmp/a.txt'), isFalse);
    });
  });
}
