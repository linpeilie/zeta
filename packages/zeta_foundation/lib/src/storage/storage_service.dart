/// 单个 UTF-8 文档的读写端口。
///
/// 基础层只负责「指定位置的读、写」：不认识主题、会话、JSON schema，也不拼
/// `~/.zeta` 路径。路径与原子性由宿主实现决定；测试注入内存实现。
///
/// 契约：
///
/// - [read] 在文档不存在时返回 `null`，其它错误交给调用方按语义处理；
/// - [write] 必须是原子替换，且同一实例上的多次写入串行执行。
abstract interface class StorageService {
  /// 读取全文；文档不存在返回 `null`。
  Future<String?> read();

  /// 原子替换全文。
  Future<void> write(String value);
}

/// 按相对键打开文档，供 turn 上下文、每会话决策这类动态文件使用。
typedef StorageServiceFactory = StorageService Function(String key);

/// 不落盘的文档，供测试与临时宿主使用。
final class MemoryStorageService implements StorageService {
  MemoryStorageService([this._contents]);

  String? _contents;

  /// 当前内容；未写入过时为 `null`。
  String? get contents => _contents;

  @override
  Future<String?> read() async => _contents;

  @override
  Future<void> write(String value) async => _contents = value;
}
