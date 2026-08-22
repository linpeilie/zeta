/// 脱敏日志端口。
///
/// 纯 Dart Package 不能依赖根 app 的 `loggerFor`，但共享内核确实需要记录诊断。
/// 这里只声明**契约**：调用方拿到一个按 scope 命名的 logger，实现由组合层安装。
///
/// 契约同时约束内容（G7）：消息只能是脱敏后的短诊断——分类、计数、identity
/// 是否匹配。**禁止**写入 prompt、回复正文、工具输出、文件内容、完整路径、
/// 环境变量、凭证、Provider raw payload 或原始错误文本。
abstract interface class ZetaLogger {
  /// 追踪级：高频、开发期定位用。
  void t(String message, {Object? error, StackTrace? stackTrace});

  /// 调试级。
  void d(String message, {Object? error, StackTrace? stackTrace});

  /// 信息级。
  void i(String message, {Object? error, StackTrace? stackTrace});

  /// 警告级：可恢复的异常路径。
  void w(String message, {Object? error, StackTrace? stackTrace});

  /// 错误级：需要用户或开发者关注的失败。
  void e(String message, {Object? error, StackTrace? stackTrace});

  /// 记录带结构化上下文的失败。
  ///
  /// [context] 只允许白名单键值：identity、状态、协议诊断分类。**脱敏由实现
  /// 负责**——内核不知道宿主的日志格式，也不该自己拼接可能带路径的字符串。
  void failure(
    String message, {
    Map<String, Object?> context = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  });
}

/// 按 scope 创建 logger 的工厂。
typedef ZetaLoggerFactory = ZetaLogger Function(String scope);

/// 全部丢弃的 logger，未安装实现时使用。
final class NoopZetaLogger implements ZetaLogger {
  const NoopZetaLogger();

  @override
  void t(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void d(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void i(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void w(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void e(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void failure(
    String message, {
    Map<String, Object?> context = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

/// 进程级日志工厂安装点。
///
/// 这是仓库里**唯一**允许的进程级可变单例：日志 sink 天然是进程资源，且
/// 现有的 `loggerFor` 本来就是全局的。它只承载"往哪写"，不承载任何业务状态；
/// 未安装时默认全部丢弃，Package 在没有宿主的测试里也能跑。
abstract final class ZetaLogging {
  static ZetaLoggerFactory _factory = _noopFactory;

  /// 由组合层在启动时安装一次。
  static void install(ZetaLoggerFactory factory) => _factory = factory;

  /// 恢复默认丢弃实现；测试用来隔离全局状态。
  static void reset() => _factory = _noopFactory;

  static ZetaLogger _noopFactory(String scope) => const NoopZetaLogger();
}

/// 取得某个 scope 的 logger。
///
/// scope 是写死在代码里的稳定标签（例如 `zeta.agent.runtime_registry`），
/// 不允许拼入运行期数据。
ZetaLogger zetaLoggerFor(String scope) => ZetaLogging._factory(scope);
