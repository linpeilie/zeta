/// 权限请求条目：流内零高度。
library;

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_hidden_entry_renderer.dart';

/// 权限审批仍在 Composer 上方的 dock 渲染，避免时间线出现重复卡片。
final class AgentPermissionRenderer
    extends AgentHiddenEntryRenderer<AgentPermissionTimelineEntry> {
  /// 创建权限条目 renderer。
  const AgentPermissionRenderer();

  @override
  Type get payloadType => AgentPermissionTimelineEntry;

  @override
  Object layoutRevision(
    AgentPermissionTimelineEntry payload,
    AgentTimelineExpansionLookup expansion,
  ) {
    final request = payload.request;
    return Object.hash(
      Object.hash(
        request.id,
        request.title,
        request.kind,
        request.command,
        request.description,
      ),
      0,
    );
  }
}
