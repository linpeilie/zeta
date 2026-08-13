import 'package:zeta/src/features/agent/data/agent_provider_static_capabilities.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

/// 为测试 Fake 提供 thread 生命周期端口的默认空实现。
///
/// 与实现对话端口的 Fake 类一起 `with` 使用；
/// 需要断言调用时，在具体 Fake 中 override 并记录参数即可。
mixin AgentProviderThreadLifecycleStub
    implements
        AgentThreadNamingPort,
        AgentThreadArchivalPort,
        AgentThreadDeletionPort,
        AgentThreadCompactionPort,
        AgentThreadBranchingPort {
  /// 测试 fake 默认模拟能力完整的 Codex；专项测试可 override。
  AgentProviderCapabilities get capabilities => AgentProviderStaticCapabilities
      .codexAppServer
      .copyWith(canForkThreadAtTurn: true);

  final List<({String threadId, String name})> renamedThreads =
      <({String threadId, String name})>[];
  final List<String> archivedThreads = <String>[];
  final List<String> unarchivedThreads = <String>[];
  final List<String> deletedThreads = <String>[];
  final List<String> forkedThreads = <String>[];
  final List<AgentForkBoundary> forkBoundaries = <AgentForkBoundary>[];
  final List<AgentPermissionRequestSnapshot> forkPermissionSnapshots =
      <AgentPermissionRequestSnapshot>[];
  final List<String> compactedThreads = <String>[];

  /// 分叉时返回的会话；为空则用 `forked-<threadId>`。
  AgentSession? forkResult;

  /// Fake 的 provider id，用于默认 fork 结果。
  String get threadLifecycleProviderId => defaultAgentProviderId;

  AgentRuntimeInfo? get runtimeInfo => null;

  AgentProviderLifecycleState get lifecycleState =>
      AgentProviderLifecycleState.stopped;

  AgentRuntimeScope? get runtimeScope => null;

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    renamedThreads.add((threadId: threadId, name: name));
  }

  @override
  Future<void> archiveThread(String threadId) async {
    archivedThreads.add(threadId);
  }

  @override
  Future<void> unarchiveThread(String threadId) async {
    unarchivedThreads.add(threadId);
  }

  @override
  Future<void> deleteThread(String threadId) async {
    deletedThreads.add(threadId);
  }

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    forkedThreads.add(threadId);
    forkBoundaries.add(boundary);
    forkPermissionSnapshots.add(permissionSnapshot);
    return forkResult ??
        AgentSession(
          id: 'forked-$threadId',
          providerId: threadLifecycleProviderId,
          title: 'Fork of $threadId',
        );
  }

  @override
  Future<void> compactThread(String threadId) async {
    compactedThreads.add(threadId);
  }
}
