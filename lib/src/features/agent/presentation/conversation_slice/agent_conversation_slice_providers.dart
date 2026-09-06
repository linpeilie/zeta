import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_ports.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_owner_key.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_session_dependencies.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_notifier.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 运行时命令面暂保留 executor 路径；WP-2 统一 Actions。
final agentConversationCommandProvider = Provider.autoDispose
    .family<AgentConversationCommandPort, AgentConversationBindingKey>(
      (ref, key) => ref.watch(agentConversationRuntimeProvider(key)),
    );

final agentConversationRuntimeProvider = Provider.autoDispose
    .family<AgentConversationRuntimeController, AgentConversationBindingKey>((
      ref,
      key,
    ) {
      final resolution = ref.read(
        agentConversationOwnerResolutionProvider(key),
      );
      if (resolution is! AgentConversationOwnerLive) {
        throw StateError('Conversation is not live');
      }
      final executor = ref
          .read(
            agentConversationSessionDependenciesProvider(resolution.ownerKey),
          )
          .executor;
      if (executor is! AgentConversationRuntimeController) {
        throw StateError('No conversation runtime');
      }
      return executor;
    });

/// BindingKey 是查询别名，真实 owner 使用 entry lifetime 身份。
final agentConversationSliceProvider = Provider.autoDispose
    .family<AgentConversationSliceState, AgentConversationBindingKey>(
      (ref, key) =>
          switch (ref.watch(agentConversationOwnerResolutionProvider(key))) {
            AgentConversationOwnerLive(:final ownerKey) => ref.watch(
              agentConversationSliceOwnerProvider(ownerKey),
            ),
            AgentConversationOwnerClosing() || AgentConversationOwnerClosed() =>
              AgentConversationSliceState.closedProjection(),
            AgentConversationOwnerUnknown() =>
              AgentConversationSliceState.unavailableProjection(),
          },
    );

// ---------------------------------------------------------------------------
// selector：只暴露 region 粒度，避免 UI 直接依赖整个切片
// ---------------------------------------------------------------------------

/// 头栏 selector。
final agentConversationHeaderProvider =
    Provider.family<AgentHeaderState, AgentConversationBindingKey>(
      (ref, key) => ref.watch(
        agentConversationSliceProvider(key).select((state) => state.header),
      ),
      name: 'agentConversationHeader',
      isAutoDispose: true,
    );

/// Composer selector。
final agentConversationComposerProvider =
    Provider.family<AgentComposerState, AgentConversationBindingKey>(
      (ref, key) => ref.watch(
        agentConversationSliceProvider(key).select((state) => state.composer),
      ),
      name: 'agentConversationComposer',
      isAutoDispose: true,
    );

/// 待处理交互 selector（四种语义仍在各自字段里，不合并）。
final agentConversationPendingInteractionProvider =
    Provider.family<AgentPendingInteractionState, AgentConversationBindingKey>(
      (ref, key) => ref.watch(
        agentConversationSliceProvider(
          key,
        ).select((state) => state.pendingInteractions),
      ),
      name: 'agentConversationPendingInteraction',
      isAutoDispose: true,
    );

/// 展开态 selector。
final agentConversationExpansionProvider =
    Provider.family<AgentExpansionState, AgentConversationBindingKey>(
      (ref, key) => ref.watch(
        agentConversationSliceProvider(key).select((state) => state.expansion),
      ),
      name: 'agentConversationExpansion',
      isAutoDispose: true,
    );

/// 历史时间线 selector。
final agentConversationHistoryProvider =
    Provider.family<AgentConversationHistoryState, AgentConversationBindingKey>(
      (ref, key) => ref.watch(
        agentConversationSliceProvider(key).select((state) => state.history),
      ),
      name: 'agentConversationHistory',
      isAutoDispose: true,
    );
