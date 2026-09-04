import 'dart:io';

import 'package:flutter/painting.dart';

ImageProvider<Object>? resolveMarkdownLocalImageProvider(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    if (uri.scheme == 'file') {
      return FileImage(File.fromUri(uri));
    }
    // Windows 盘符会被解析成单字母 scheme（`C:\a\b.png` → scheme `c`），
    // 按 scheme 拒绝会让 Windows 上的本地图片全部加载不出来。真实 URL scheme
    // 至少两个字符，单字母一律当路径处理。
    if (uri.scheme.length > 1) {
      return null;
    }
  }

  final file = File(trimmed);
  if (file.isAbsolute || file.existsSync()) {
    return FileImage(file);
  }

  return null;
}
