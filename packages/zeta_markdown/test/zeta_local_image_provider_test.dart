import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_markdown/src/render/local_image_provider_io.dart';

/// Zeta 侧新增的回归测试（见 `UPSTREAM.md`：本地改动的测试放独立文件，
/// 上游同名测试文件保持与上游对齐，同步时只需 diff 那一个）。
void main() {
  test('绝对路径解析为 FileImage：Windows 盘符不能被当成 URI scheme', () {
    // 这是 T1 修掉的上游缺陷的守卫：`C:\...` 会被 Uri.tryParse 解析成
    // scheme `c`，按 scheme 非空拒绝会让 Windows 上本地图片全部加载不出来。
    // 在 Windows 上这条路径带盘符，在 Linux/macOS 上是普通绝对路径，
    // 两边都能跑到「绝对路径必须成图」的断言。
    final absolutePath = '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'zeta_markdown_missing_image.png';

    expect(resolveMarkdownLocalImageProvider(absolutePath), isA<FileImage>());
  });

  test('Windows 盘符字面量解析为 FileImage', () {
    expect(
      resolveMarkdownLocalImageProvider(r'C:\tmp\zeta_markdown_image.png'),
      isA<FileImage>(),
    );
  }, testOn: 'windows');

  test('file: URI 解析为 FileImage', () {
    expect(
      resolveMarkdownLocalImageProvider('file:///tmp/zeta_markdown_image.png'),
      isA<FileImage>(),
    );
  });

  test('远程与非法 scheme 一律拒绝', () {
    for (final source in <String>[
      'https://example.com/a.png',
      'http://example.com/a.png',
      'data:image/png;base64,AAAA',
      '',
      '   ',
    ]) {
      expect(
        resolveMarkdownLocalImageProvider(source),
        isNull,
        reason: source,
      );
    }
  });
}
