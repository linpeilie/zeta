/// 用户提问条目：流内零高度。
library;

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/presentation/agent_timeline_extent_descriptor.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_hidden_entry_renderer.dart';

/// 提问同样在 Composer 上方的 dock 渲染。
final class AgentQuestionRenderer
    extends AgentHiddenEntryRenderer<AgentQuestionTimelineEntry> {
  /// 创建提问条目 renderer。
  const AgentQuestionRenderer();

  @override
  Type get payloadType => AgentQuestionTimelineEntry;

  @override
  Object layoutRevision(
    AgentQuestionTimelineEntry payload,
    AgentTimelineExpansionLookup expansion,
  ) {
    final request = payload.request;
    return Object.hash(
      Object.hash(
        request.id,
        request.title,
        request.description,
        request.questions.length,
      ),
      0,
    );
  }
}
