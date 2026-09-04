/// 时间线 renderer 的默认注册清单。
///
/// **新增一种时间线条目 = 新增一个 renderer 文件 + 在这里加一行。** 其余四处
/// （分组归约除外的 extent 估算 / 展开指纹 / Widget 构建 / 导航谓词）都由注册表
/// 统一分发，不再逐处补分支。
library;

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderer_registry.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_command_group_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_file_edit_group_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_history_event_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_message_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_permission_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_plan_approval_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_question_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_tool_call_renderer.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/renderers/agent_turn_file_changes_renderer.dart';

/// entry 级 renderer 清单（7 条）。
///
/// 命令集需要按条目查指纹，所以先单独建这一层，再把查表闭包注入命令集
/// renderer——组内条目的指纹归条目自己的 renderer 所有。
List<AgentTimelineRenderer<Object>> _entryRenderers() {
  return <AgentTimelineRenderer<Object>>[
    const AgentMessageRenderer(),
    const AgentToolCallRenderer(),
    const AgentPermissionRenderer(),
    const AgentQuestionRenderer(),
    const AgentPlanApprovalRenderer(),
    const AgentTurnFileChangesRenderer(),
    const AgentHistoryEventRenderer(),
  ];
}

/// 创建默认注册表（entry 级 7 条 + block 级 2 条）。
AgentTimelineRendererRegistry buildAgentTimelineRendererRegistry() {
  final entryRenderers = _entryRenderers();
  final byEntryType = <Type, AgentTimelineRenderer<Object>>{
    for (final renderer in entryRenderers) renderer.payloadType: renderer,
  };

  Object entryLayoutRevision(
    AgentTimelineEntry entry,
    AgentTimelineExpansionLookup expansion,
  ) {
    final renderer = byEntryType[entry.runtimeType];
    if (renderer == null) {
      throw UnsupportedError('未注册的时间线渲染类型: ${entry.runtimeType}');
    }
    return renderer.layoutRevision(entry, expansion);
  }

  return AgentTimelineRendererRegistry(<AgentTimelineRenderer<Object>>[
    ...entryRenderers,
    AgentCommandGroupRenderer(entryLayoutRevision: entryLayoutRevision),
    const AgentFileEditGroupRenderer(),
  ]);
}
