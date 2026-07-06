import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Agent provider 的统一能力接口。
///
/// UI 只依赖这个接口，不关心底层是 Codex app-server、ACP 还是 Claude Code CLI。
/// 每个 provider 负责把自己的协议事件映射成 [AgentEvent]。
abstract class AgentProvider {
  /// 当前 provider 的启动和显示配置。
  AgentProviderConfig get config;

  /// provider 推送给 UI 的状态、消息、工具调用和审批事件。
  Stream<AgentEvent> get events;

  /// 初始化 provider。
  ///
  /// 对 Codex V1 来说，这一步会启动 `codex app-server --stdio` 并发送
  /// JSON-RPC `initialize`。
  Future<void> initialize();

  /// 创建新会话。
  Future<AgentSession> startSession({required AgentContext context});

  /// 恢复已有会话。
  ///
  /// 如果底层 provider 无法恢复，调用方可以回退到 [startSession]。
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
  });

  /// 分页读取指定项目下的 thread 摘要列表。
  Future<AgentThreadPage> listThreads({required AgentThreadListQuery query});

  /// 拉取 provider 支持的模型列表。
  ///
  /// 对 Codex 而言会在 initialize 握手后自动拉取，其他 provider 可返回空列表。
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  });

  /// 更新 provider 内存中的模型选择，后续 turn/start 会使用该选择覆盖默认 model。
  ///
  /// 持久化由调用方（controller/ViewModel）负责，此方法只同步运行时状态。
  void updateModelSelection(AgentModelSelection selection);

  /// 读取 thread 历史消息与工具记录。
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  });

  /// 在会话中发起一个新回合。
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required String message,
    required AgentContext context,
  });

  /// 在正在运行的回合中追加用户指令。
  Future<void> steerTurn({
    required AgentSession session,
    required String message,
    required AgentContext context,
  });

  /// 取消正在运行的回合。
  Future<void> cancelTurn(AgentTurn turn);

  /// 回写用户对权限请求的决定。
  Future<void> respondToPermission(AgentPermissionDecision decision);

  /// 释放进程、订阅和流。
  Future<void> dispose();
}

/// 根据 provider 配置创建具体实现。
///
/// 测试可以注入 fake factory，生产环境使用默认 factory。
abstract class AgentProviderFactory {
  /// 创建一个可用的 provider 实例。
  AgentProvider create(AgentProviderConfig config);
}
