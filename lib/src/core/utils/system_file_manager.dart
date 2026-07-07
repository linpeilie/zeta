import 'dart:io';

typedef ProjectLocationOpener = Future<void> Function(String path);

/// 在桌面平台使用系统文件管理器打开目录。
Future<void> openPathInSystemFileManager(String path) async {
  final directory = Directory(path);
  if (!await directory.exists()) {
    throw FileSystemException('Directory does not exist', path);
  }

  if (Platform.isWindows) {
    await Process.start('explorer.exe', <String>[
      path,
    ], mode: ProcessStartMode.detached);
    return;
  }

  if (Platform.isMacOS) {
    await Process.start('open', <String>[
      path,
    ], mode: ProcessStartMode.detached);
    return;
  }

  await Process.start('xdg-open', <String>[
    path,
  ], mode: ProcessStartMode.detached);
}
