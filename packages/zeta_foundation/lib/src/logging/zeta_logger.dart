/// 脱敏日志端口。
///
/// 纯 Dart Package 不能依赖根 app 的 `loggerFor`，但共享内核确实需要记录诊断。
/// 这里只声明**契约**：调用方拿到一个按 scope 命名的 logger，实现由组合层安装。
///
/// ## 内容契约（G7）
///
/// - **调用方**：`message` 只能是脱敏后的短诊断——分类、计数、identity 是否匹配。
///   不得自己拼接 prompt、回复正文、工具输出、文件内容、完整路径或凭证。
/// - **实现方**：`error` / `stackTrace` 收的是**原始异常对象**——诊断离不开异常
///   类型与栈，但它们的 `toString()` 常常带 token、密码和本机路径。因此
///   **实现必须在渲染/落盘前完成脱敏**，控制台与文件输出使用同一条链路。
///   端口不能靠"禁止传 error"来保证安全：那样调用方只会把异常拼进 message，
///   反而更难脱敏。
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

/// 异常可实现此接口，为 [ZetaLogger.failure] 补充协议诊断字段。
///
/// 契约与 [ZetaLogger] 一致：`logDiagnostic` 只放分类、状态码、identity
/// 是否匹配这类脱敏信息，不放 payload 正文。
abstract interface class StructuredLogDiagnostic {
  Object? get logDiagnostic;
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
/// 目标架构 §12 规则 10 禁止全局 service locator 与可变 singleton。**日志 sink
/// 是这条规则唯一登记在案的例外**（见目标架构 §12 的例外说明）：它只承载
/// "往哪写"，不承载任何业务状态与身份；替代方案是把 logger 穿过几十个构造点，
/// 而默认值一旦漏注入就会静默丢日志——那比一个受限的全局更危险。
///
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
///
/// 返回的是**延迟代理**：每次写日志时才解析当前工厂。调用方普遍写成
/// `final _log = zetaLoggerFor('...')` 顶层惰性字段，如果这里直接返回实例，
/// 只要有一次访问发生在 `install()` 之前，该 scope 就会**永久**持有 no-op
/// 实现，之后所有日志静默消失。
ZetaLogger zetaLoggerFor(String scope) => _DeferredZetaLogger(scope);

/// 每次调用都重新解析工厂的 logger 代理。
final class _DeferredZetaLogger implements ZetaLogger {
  const _DeferredZetaLogger(this._scope);

  final String _scope;

  ZetaLogger get _delegate => ZetaLogging._factory(_scope);

  @override
  void t(String message, {Object? error, StackTrace? stackTrace}) =>
      _delegate.t(message, error: error, stackTrace: stackTrace);

  @override
  void d(String message, {Object? error, StackTrace? stackTrace}) =>
      _delegate.d(message, error: error, stackTrace: stackTrace);

  @override
  void i(String message, {Object? error, StackTrace? stackTrace}) =>
      _delegate.i(message, error: error, stackTrace: stackTrace);

  @override
  void w(String message, {Object? error, StackTrace? stackTrace}) =>
      _delegate.w(message, error: error, stackTrace: stackTrace);

  @override
  void e(String message, {Object? error, StackTrace? stackTrace}) =>
      _delegate.e(message, error: error, stackTrace: stackTrace);

  @override
  void failure(
    String message, {
    Map<String, Object?> context = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) => _delegate.failure(
    message,
    context: context,
    error: error,
    stackTrace: stackTrace,
  );
}
