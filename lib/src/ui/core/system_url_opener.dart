import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用系统默认浏览器打开外链。
///
/// G7：url 属用户内容，不进日志与指标；失败只回报 false，不带回 url 片段。
abstract interface class SystemUrlOpener {
  /// 打开 [url]；返回是否受理。非 http(s) 一律拒绝。
  Future<bool> openUrl(String url);
}

/// 组合根必须覆盖：生产装 [ProcessSystemUrlOpener]，测试装记录型 fake。
final systemUrlOpenerProvider = Provider<SystemUrlOpener>(
  (ref) => throw StateError('systemUrlOpenerProvider must be overridden'),
  name: 'systemUrlOpener',
);

/// 交给平台默认处理程序打开。
///
/// 走 [Process.start] 传参数组、不经 shell，url 不会被当成命令拼接。
final class ProcessSystemUrlOpener implements SystemUrlOpener {
  /// 创建系统外链打开器。
  const ProcessSystemUrlOpener();

  @override
  Future<bool> openUrl(String url) async {
    if (!isOpenableExternalUrl(url)) {
      return false;
    }
    final target = url.trim();
    try {
      if (Platform.isWindows) {
        // explorer.exe 会转交默认浏览器；不用 `cmd /c start`——那条路径要处理
        // 标题参数与引号转义，多一个注入面。
        await Process.start('explorer.exe', <String>[
          target,
        ], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', <String>[
          target,
        ], mode: ProcessStartMode.detached);
        return true;
      }
      await Process.start('xdg-open', <String>[
        target,
      ], mode: ProcessStartMode.detached);
      return true;
    } on ProcessException {
      // 缺少 xdg-open 之类的环境问题：静默失败，不把 url 写进日志。
      return false;
    }
  }
}

/// 是否为允许交给系统浏览器的外链。
///
/// 白名单只有 http/https（fail-closed）：`javascript:` / `file:` / `ftp:` /
/// `data:` 这些要么能执行脚本，要么能拉起本机程序或读本地文件。
bool isOpenableExternalUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return false;
  }
  // 协议对但没有主机（`http:///a`、`https:`）同样拒绝：交给系统会得到意外行为。
  return uri.host.isNotEmpty;
}
