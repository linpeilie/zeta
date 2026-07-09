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

  /// 更新审批/沙箱策略选择，后续 turn/start 与 thread/start 会携带该策略。
  void updatePermissionSelection(AgentPermissionSelection selection);

  /// 拉取 `permissionProfile/list`；失败或未支持时返回空列表。
  Future<List<AgentPermissionProfileSummary>> listPermissionProfiles();

  /// Guardian 拒绝后的人工放行（`thread/approveGuardianDeniedAction`）。
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  });

  /// 读取 thread 历史消息与工具记录。
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
  });

  /// 取消对指定 thread 的服务端通知订阅。
  ///
  /// 切换会话时调用，避免旧 thread 的通知继续到达本端。
  /// 实现应为 best-effort：线程未加载/未订阅时不应视为失败。
  Future<void> unsubscribeThread(String threadId);

  /// 重命名 thread（对应 `thread/name/set`）。
  Future<void> renameThread({required String threadId, required String name});

  /// 归档 thread（对应 `thread/archive`）。
  Future<void> archiveThread(String threadId);

  /// 取消归档 thread（对应 `thread/unarchive`）。
  Future<void> unarchiveThread(String threadId);

  /// 永久删除 thread（对应 `thread/delete`）。
  Future<void> deleteThread(String threadId);

  /// 从既有 thread 分叉出新会话（对应 `thread/fork`）。
  ///
  /// 返回新会话；调用方应切换到该会话并加载其历史。
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
  });

  /// 回滚 thread 末尾若干回合（对应 `thread/rollback`）。
  ///
  /// 仅修改会话历史，**不**还原 agent 已写入的本地文件。
  /// 返回回滚后的历史快照（含 turns）。
  Future<AgentThreadHistorySnapshot> rollbackThread({
    required String threadId,
    required int numTurns,
  });

  /// 启动上下文压缩（对应 `thread/compact/start`）。
  Future<void> compactThread(String threadId);

  /// 在会话中发起一个新回合。
  ///
  /// [message] 为纯文本快捷参数；若同时提供 [inputs]，以 [inputs] 为准。
  /// [inputs] 可包含文本与本地图片等多项用户输入。
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  });

  /// 在正在运行的回合中追加用户指令。
  ///
  /// 语义同 [sendMessage]：优先使用 [inputs]，否则回退到 [message]。
  Future<void> steerTurn({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
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
