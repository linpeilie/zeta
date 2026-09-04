import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/ui/core/system_url_opener.dart';

/// 记录型外链打开器：widget test 一律不许真去拉起系统浏览器。
///
/// 白名单判定复用生产的 [isOpenableExternalUrl]，所以用例断言的「哪些 url 会被
/// 受理」与生产实现同源；[opened] 只收下被受理的那些。
final class RecordingSystemUrlOpener implements SystemUrlOpener {
  /// 创建记录型打开器。
  RecordingSystemUrlOpener();

  /// 受理并「打开」过的 url，按调用顺序。
  final List<String> opened = <String>[];

  /// 被白名单拒绝的 url，按调用顺序。
  final List<String> rejected = <String>[];

  @override
  Future<bool> openUrl(String url) async {
    if (!isOpenableExternalUrl(url)) {
      rejected.add(url);
      return false;
    }
    opened.add(url.trim());
    return true;
  }
}

/// 装一个记录型打开器；不传就现建一个。
Override recordingSystemUrlOpenerOverride([RecordingSystemUrlOpener? opener]) {
  return systemUrlOpenerProvider.overrideWithValue(
    opener ?? RecordingSystemUrlOpener(),
  );
}
