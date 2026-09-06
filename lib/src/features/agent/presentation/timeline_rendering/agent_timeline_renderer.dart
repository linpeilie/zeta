/// 时间线渲染分发的核心契约：一种 payload 类型 = 一个 renderer。
///
/// 一种卡片的渲染职责原先散在四处（分组归约 / extent 估算 / 展开指纹 /
/// Widget 构建 / 导航谓词），漏改 extent 就会引发滚动跳动。这里把「构建 +
/// 估算 + 布局指纹 + 目录谓词 + 保温」收敛成单个条目，新增类型只加一个文件。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_actions.dart';
import 'package:zeta/src/features/agent/presentation/agent_markdown_cache.dart';
import 'package:zeta/src/features/agent/presentation/agent_plan_revision_drafts.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_extent_math.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';

/// 渲染上下文：renderer 需要的**稳定**外部依赖，每个 AgentPane 创建一次。
///
/// 逐 build 变化的量（turn / pendingState / isLive）不进这里——否则 context
/// 必须每帧重建，「创建一次」就不成立；它们作为调用点参数传入。
final class AgentTimelineRenderContext {
  /// 创建渲染上下文。
  const AgentTimelineRenderContext({
    required this.controller,
    required this.actions,
    required this.bindingKey,
    required this.markdownCache,
    required this.planRevisionDrafts,
  });

  /// 会话运行时协调器。
  ///
  /// 卡片当前统一接收它（仅供现有只读查询）；需要窄依赖的
  /// renderer 用 [actions] / [bindingKey] 两个只读面，不要新增对它的耦合。
  final AgentConversationRuntimeController controller;

  /// Markdown 渲染缓存（含保温）。
  final AgentMarkdownCache markdownCache;

  /// 计划修订草稿的输入控制器仓库。
  final AgentPlanRevisionDraftStore planRevisionDrafts;

  /// 命令执行面（窄接口）。
  final AgentConversationActions actions;

  /// 本会话的冻结 Binding 身份，`AgentRegionBuilder` 用它分键订阅。
  final AgentConversationBindingKey bindingKey;
}

/// 单个 payload 类型的完整渲染条目。
///
/// payload 可能是 block（命令集 / 文件编辑组），也可能是 entry（消息 / 工具卡
/// / …）——注册表在 resolve 时会对 [AgentTimelineEntryRenderBlock] 解包。
///
/// 泛型说明：Dart 泛型类协变，`AgentTimelineRenderer<AgentMessageTimelineEntry>`
/// 可直接当作 `AgentTimelineRenderer<Object>` 使用；注册表按精确 runtimeType
/// 解析，入参的运行时类型必然匹配，协变插入的运行时检查不会触发。
abstract interface class AgentTimelineRenderer<P extends Object> {
  /// 该 renderer 接管的 payload 运行时类型（entry 类型或 block 类型）。
  Type get payloadType;

  /// extent 工厂用的稳定 kind 字符串。
  ///
  /// 取值必须是 [AgentTimelineExtentKinds] 既有常量。它不是常量 getter：消息
  /// 条目的 kind 取决于 role 与是否 plan（user / agentMarkdown / plan /
  /// system），而 kind 决定虚拟化列表的测量 cohort，收敛成一个值会改变行为。
  String kindOf(P payload);

  /// 构建 Widget。
  ///
  /// [turn] 与 [pendingState] 随调用点传入（payload 里没有 turn 概念；
  /// live turn 的判断是 `controller.liveTurnState?.id == turn.id`）。
  Widget build(
    BuildContext context,
    P payload,
    AgentTimelineRenderContext renderContext, {
    required AgentConversationTurnGroup turn,
    required AgentPendingInteractionState pendingState,
  });

  /// 估算主轴高度（logical px）。
  ///
  /// 语义与 extent 工厂现状一致：输入交叉轴宽度 / 文本缩放 / 展开态 / 操作组
  /// 邻接，输出冷启动估算高度。
  double estimateExtent(
    P payload, {
    required double crossAxisExtent,
    required double textScale,
    required AgentTimelineExpansionLookup expansion,
    required bool precededByOperationGroup,
    required bool followedByOperationGroup,
  });

  /// 布局修订指纹：payload 内容或展开态变化必须改变返回值。
  ///
  /// 只覆盖 payload 自身；turn id、block id 与操作组邻接由 extent 工厂在外层
  /// 合成，renderer 不重复。
  Object layoutRevision(P payload, AgentTimelineExpansionLookup expansion);

  /// 是否计入导航目录。
  bool get rendersInline;

  /// 可选：Sliver child 创建前的保温准备。
  ///
  /// 返回非 null 时列表层包 `ValueListenableBuilder` + `KeepAlive`；默认
  /// null 表示不保温。[isLive] 取 viewport item 的 live 标志（增量更新偏好的
  /// 数据源）。目前只有 agent 正文 markdown 消息实现它。
  ValueListenable<bool>? prepareWarmEntry(
    P payload,
    AgentTimelineRenderContext renderContext, {
    required bool isLive,
  });
}

/// [AgentTimelineRenderer] 的默认实现基类。
///
/// 提供 [rendersInline] 与 [prepareWarmEntry] 的默认取值，让绝大多数 renderer
/// 只需要写 4 个方法。接口本身保持无默认实现，便于测试注入裁剪版。
abstract base class AgentTimelineRendererBase<P extends Object>
    implements AgentTimelineRenderer<P> {
  /// 创建 renderer。
  const AgentTimelineRendererBase();

  @override
  bool get rendersInline => true;

  @override
  ValueListenable<bool>? prepareWarmEntry(
    P payload,
    AgentTimelineRenderContext renderContext, {
    required bool isLive,
  }) => null;
}
