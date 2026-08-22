/// 单个 UTF-8 文本文件的读写端口。
///
/// 纯 Dart 层不能碰 `dart:io`，但需要持久化的模块（Provider 适配器、feature
/// store）确实要读写自己的状态文件。端口把"往哪写、怎么保证原子性"留给宿主：
/// 应用注入 `AtomicTextFile`（同目录临时文件 + rename），测试注入内存实现。
///
/// 契约：
///
/// - [read] 在文件不存在时返回 `null`，其它文件系统异常交给调用方按语义处理；
/// - [write] 必须是原子替换，且同一实例上的多次写入串行执行。
abstract interface class ZetaTextFile {
  /// 读取全文；文件不存在返回 `null`。
  Future<String?> read();

  /// 原子替换全文。
  Future<void> write(String value);
}

/// 不落盘的文本文件，供测试与无文件持久化宿主使用。
final class MemoryZetaTextFile implements ZetaTextFile {
  MemoryZetaTextFile([this._contents]);

  String? _contents;

  /// 当前内容；未写入过时为 `null`。
  String? get contents => _contents;

  @override
  Future<String?> read() async => _contents;

  @override
  Future<void> write(String value) async => _contents = value;
}
