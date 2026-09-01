import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 平台 `WindowListener` 只允许出现在窗口模块与关窗 hook。
///
/// `MainApp` / `IdeHome` / feature Widget 禁止再 mixin：窗口事件由
/// `ZetaWindowSurfaceNotifier` 翻译成快照，消费方只读状态。
void main() {
  test('lib 里 with WindowListener 只出现在窗口表面与关窗 hook', () {
    const allowed = <String>{
      'lib/src/app/window/zeta_window_surface.dart',
      'lib/src/app/window_bootstrap.dart',
    };
    final offenders = <String>[];
    for (final file in _dartFilesUnder('lib')) {
      final path = _posix(file.path);
      if (allowed.contains(path)) {
        continue;
      }
      final source = file.readAsStringSync();
      if (source.contains('with WindowListener')) {
        offenders.add(path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '平台 WindowListener 只能出现在 zeta_window_surface.dart 与 '
          'window_bootstrap.dart。请改读 zetaWindowSurfaceProvider：\n'
          '${offenders.join('\n')}',
    );
  });
}

Iterable<File> _dartFilesUnder(String directory) {
  return Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}

String _posix(String path) => path.replaceAll(r'\', '/');
