import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Data adapter 的统一生命周期宿主与 bundle 适配入口。
///
/// Application / Presentation 依赖 [AgentProviderBundle] 的中立端口，不直接持有本接口。
/// 每个 provider 负责把自己的协议事件映射成 [AgentEvent]。
abstract class AgentProvider {
  /// 当前 provider 的启动和显示配置。
  AgentProviderConfig get config;

  /// 当前 provider 的可用能力；握手后允许返回更精确的协商结果。
  AgentProviderCapabilities get capabilities;

  /// provider 推送给 UI 的状态、消息、工具调用和审批事件。
  Stream<AgentEvent> get events;

  /// 初始化 provider。
  ///
  /// 对 Codex V1 来说，这一步会启动 `codex app-server`（默认 stdio）并发送
  /// JSON-RPC `initialize`。
  Future<void> initialize();

  /// 创建新会话。
  ///
  /// [permissionSnapshot] 为 application 冻结的请求级中立权限快照。
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  });

  /// 恢复已有会话。
  ///
  /// 如果底层 provider 无法恢复，调用方可以回退到 [startSession]。
  /// [permissionSnapshot] 语义同 [startSession]。
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  });

  /// 分页读取指定项目下的 thread 摘要列表。
  Future<AgentThreadPage> listThreads({required AgentThreadListQuery query});

  /// 拉取 provider 支持的模型列表。
  ///
  /// 对 Codex 而言会在 initialize 握手后按需拉取，其他 provider 可返回空列表。
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  });

  /// 更新 provider 内存中的模型选择，后续 turn/start 会使用该选择覆盖默认 model。
  ///
  /// 持久化由调用方（controller/ViewModel）负责，此方法只同步运行时状态。
  void updateModelSelection(AgentModelSelection selection);

  /// Guardian 拒绝后的人工放行（`thread/approveGuardianDeniedAction`）。
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  });

  /// 读取 thread 历史消息与工具记录。
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  });

  /// 取消对指定 thread 的服务端通知订阅。
  ///
  /// 仅在对应消费者明确关闭/解绑 thread 时调用；共享 Provider 中切换到其他会话
  /// 不得自动退订仍被其他 Pane 使用的 thread。
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
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  });

  /// 启动上下文压缩（对应 `thread/compact/start`）。
  Future<void> compactThread(String threadId);

  /// 在会话中发起一个新回合。
  ///
  /// [message] 为纯文本快捷参数；若同时提供 [inputs]，以 [inputs] 为准。
  /// [inputs] 可包含文本与本地图片等多项用户输入。
  /// [configuration] 是仅属于本回合的不可变配置快照；空配置保持 Provider 原有行为。
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  });

  /// 在正在运行的回合中追加用户指令。
  ///
  /// 语义同 [sendMessage]：优先使用 [inputs]，否则回退到 [message]。
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
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

/// 初始化后可提供运行时版本与兼容诊断的 provider 可选接口。
abstract interface class AgentRuntimeInfoProvider {
  AgentRuntimeInfo? get runtimeInfo;
}

/// 暴露 Provider 当前生命周期，用于连接切换与诊断的可选接口。
abstract interface class AgentRuntimeLifecycleProvider {
  AgentProviderLifecycleState get lifecycleState;
}

/// 暴露当前连接 scope，供 application 隔离旧 listener 事件。
abstract interface class AgentRuntimeScopeProvider {
  AgentRuntimeScope? get runtimeScope;
}

/// 支持独立用户提问回写的 Provider 可选接口。
///
/// Permission-only Provider 无需实现，避免把空 answers 伪装成审批决定。
abstract interface class AgentQuestionResponseProvider {
  Future<void> respondToQuestion(AgentQuestionResponse response);
}

/// 支持远端 thread 订阅释放的 Provider 可选接口。
///
/// 仅真实拥有订阅模型的 adapter 实现；无订阅的 Provider 不得实现，
/// 以便 Bundle 把 [AgentThreadSubscriptionPort] 留空。
abstract interface class AgentThreadSubscriptionProvider {
  Future<void> unsubscribeThread(String threadId);
}

/// 支持绕过实例内存缓存、重新读取模型目录的 Provider 可选接口。
abstract interface class AgentRefreshableModelCatalogProvider {
  Future<AgentModelList> refreshModels({
    int limit = 20,
    bool includeHidden = false,
  });
}

/// 支持发现对话运行模式目录的 Provider 可选接口。
///
/// 实现该接口只表示适配器具备目录探测入口；运行时是否已确认可用仍由
/// [AgentProviderCapabilities.supportsModeSelection] 表达。
abstract interface class AgentConversationModeCatalogProvider {
  /// 读取当前 Provider 运行时可用的对话模式预设。
  Future<AgentConversationModeCatalog> listConversationModes();
}

/// 直接暴露中立权限策略 port 的 Provider 可选接口。
///
/// [AgentProviderBundle.adapt] 仅在实现本接口时暴露
/// [AgentProviderBundle.permissionPolicy]；否则 port 为 null（UI 隐藏选择器）。
abstract interface class AgentPermissionPolicyProvider {
  /// Provider 拥有的权限策略 port（通常为 data 层 adapter）。
  AgentPermissionPolicyPort get permissionPolicy;
}

/// 支持 Skill 目录发现的 Provider 可选接口。
///
/// 实现该接口只表示适配器具备 `skills/list` 入口；UI 是否展示仍由
/// [AgentProviderCapabilities.supportsSkillInput] 门控。
abstract interface class AgentSkillsCatalogProvider {
  /// 读取指定 cwd 下可用的 skill 目录。
  Future<AgentSkillsCatalog> listSkills({
    List<String> cwds = const <String>[],
    bool forceReload = false,
  });

  /// Skill 文件变更失效信号；无 payload，收到后应重新 list。
  Stream<void> get skillsChanged;
}

/// Provider 拥有本地会话索引时，可只移除客户端列表记录而不删除服务端历史。
///
/// 该操作与 [AgentProvider.deleteThread] 语义严格分离，UI 必须明确提示用户远端
/// 会话仍然保留。
abstract interface class AgentLocalThreadListProvider {
  Future<void> removeThreadFromList(String threadId);
}

/// 支持 session 动态配置的 provider 可选接口。
abstract interface class AgentSessionConfigProvider {
  List<AgentSessionConfigOption> sessionConfigOptions(String sessionId);

  Future<void> setSessionConfigOption({
    required String sessionId,
    required String configId,
    required Object value,
  });
}

/// 支持独立计划审批的 provider 可选接口。
abstract interface class AgentPlanApprovalProvider {
  Future<void> respondToPlanApproval(AgentPlanApprovalDecision decision);
}

/// 根据 provider 配置创建具体实现。
///
/// 测试可以注入 fake factory，生产环境使用默认 factory。
abstract class AgentProviderFactory {
  /// 创建一个可用的 provider 实例。
  AgentProvider create(AgentProviderConfig config);
}
