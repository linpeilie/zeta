import 'package:zeta_agent_core/src/domain/agent_turn_context_models.dart';

/// Zeta 发起 turn 时记录的会话上下文存储边界。
///
/// 端口留在中立内核，文件实现留在 data 层：内核只声明"要能读写 turn 上下文"，
/// 不关心它落在 `~/.zeta` 还是内存里。
abstract interface class AgentTurnContextStore {
  Future<AgentThreadTurnContext?> load({
    required String providerId,
    required String threadId,
  });

  Future<void> save(AgentThreadTurnContext context);
}

/// 不落盘的会话上下文，供测试和无文件持久化宿主使用。
final class MemoryAgentTurnContextStore implements AgentTurnContextStore {
  MemoryAgentTurnContextStore({
    Map<String, AgentThreadTurnContext> contexts =
        const <String, AgentThreadTurnContext>{},
  }) : _contexts = <String, AgentThreadTurnContext>{...contexts};

  final Map<String, AgentThreadTurnContext> _contexts;

  @override
  Future<AgentThreadTurnContext?> load({
    required String providerId,
    required String threadId,
  }) async {
    return _contexts[_key(providerId, threadId)];
  }

  @override
  Future<void> save(AgentThreadTurnContext context) async {
    _contexts[_key(context.providerId, context.threadId)] = context;
  }

  /// 与拆包前的 data 层实现保持同一套键格式（trim + NUL 分隔），
  /// 否则既有调用点与测试里预置的键会失配。
  String _key(String providerId, String threadId) =>
      '${providerId.trim()}\u0000${threadId.trim()}';
}
