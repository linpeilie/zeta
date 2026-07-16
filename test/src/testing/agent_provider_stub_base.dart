import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';

/// 为测试用 [AgentProvider] 提供 Phase 2 thread 生命周期方法的默认空实现。
///
/// 与 `implements AgentProvider` 的 Fake 类一起 `with` 使用；
/// 需要断言调用时，在具体 Fake 中 override 并记录参数即可。
mixin AgentProviderThreadLifecycleStub {
  /// 测试 fake 默认模拟能力完整的 Codex；专项测试可 override。
  AgentProviderCapabilities get capabilities => AgentProviderCapabilities
      .codexAppServer
      .copyWith(canForkThreadAtTurn: true);

  final List<({String threadId, String name})> renamedThreads =
      <({String threadId, String name})>[];
  final List<String> archivedThreads = <String>[];
  final List<String> unarchivedThreads = <String>[];
  final List<String> deletedThreads = <String>[];
  final List<String> forkedThreads = <String>[];
  final List<AgentForkBoundary> forkBoundaries = <AgentForkBoundary>[];
  final List<String> compactedThreads = <String>[];

  /// 分叉时返回的会话；为空则用 `forked-<threadId>`。
  AgentSession? forkResult;

  /// Fake 的 provider id，用于默认 fork 结果。
  String get threadLifecycleProviderId => defaultAgentProviderId;

  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    renamedThreads.add((threadId: threadId, name: name));
  }

  Future<void> archiveThread(String threadId) async {
    archivedThreads.add(threadId);
  }

  Future<void> unarchiveThread(String threadId) async {
    unarchivedThreads.add(threadId);
  }

  Future<void> deleteThread(String threadId) async {
    deletedThreads.add(threadId);
  }

  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
  }) async {
    forkedThreads.add(threadId);
    forkBoundaries.add(boundary);
    return forkResult ??
        AgentSession(
          id: 'forked-$threadId',
          providerId: threadLifecycleProviderId,
          title: 'Fork of $threadId',
        );
  }

  Future<void> compactThread(String threadId) async {
    compactedThreads.add(threadId);
  }
}
