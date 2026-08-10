/// 将 Agent timeline viewport item 投影为通用 [IdeVirtualItemDescriptor]。
///
/// 只做冷启动估算与 layoutRevision 指纹；不依赖 BuildContext / Provider raw
/// payload。cohort 均值不得在此批量回写已有未知项。
library;

import 'dart:math' as math;

import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_projection.dart';
import 'package:zeta/src/ui/core/virtualization/ide_virtual_item.dart';

/// 展开态查询，避免 descriptor 工厂依赖完整 ViewModel。
typedef AgentTimelineExpansionLookup = ({
  bool Function(String commandGroupId) isCommandGroupExpanded,
  bool Function(String fileEditItemId) isFileEditItemExpanded,

  /// 该 plan 消息是否已升级为带底部输入的交互卡（形态与高度都不同）。
  bool Function(String messageId) isPlanMessageInteractive,
});

/// Agent item kind 常量（仅用于估算，不参与业务分支）。
abstract final class AgentTimelineExtentKinds {
  static const userMessage = 'userMessage';
  static const agentMarkdown = 'agentMarkdown';
  static const plan = 'plan';
  static const toolCard = 'toolCard';
  static const commandGroup = 'commandGroup';
  static const fileEditGroup = 'fileEditGroup';
  static const planInteraction = 'planInteraction';
  static const liveActivity = 'liveActivity';
  static const turnFooter = 'turnFooter';
  static const system = 'system';
  static const hidden = 'hidden';
}

/// 布局环境输入（宽度 / 缩放 / locale），用于构造 [IdeLayoutEpoch]。
final class AgentTimelineLayoutContext {
  /// 创建布局上下文。
  const AgentTimelineLayoutContext({
    required this.crossAxisExtent,
    required this.devicePixelRatio,
    required this.textScale,
    required this.localeKey,
    this.typographyEpoch = 0,
  });

  /// 时间线可用交叉轴宽度（logical px）。
  final double crossAxisExtent;

  /// 设备像素比。
  final double devicePixelRatio;

  /// 文本缩放因子。
  final double textScale;

  /// locale 键。
  final String localeKey;

  /// 字体/排版版本。
  final Object typographyEpoch;

  /// 量化后的 layout epoch。
  IdeLayoutEpoch toEpoch() {
    final physical = (crossAxisExtent * devicePixelRatio).round().clamp(
      0,
      1 << 30,
    );
    // textScale 量化到 0.05，降低浮点抖动。
    final scaleKey = (textScale * 20).round() / 20.0;
    return IdeLayoutEpoch(
      crossAxisExtentInPhysicalPixels: physical,
      textScaleKey: scaleKey,
      localeKey: localeKey,
      typographyEpoch: typographyEpoch,
    );
  }
}

/// Agent timeline → [IdeVirtualItemDescriptor] 工厂。
///
/// 可复用实例：连续 [describeAll] 在 id 序列稳定时复用未变项的 descriptor
/// 对象，使尾部变化时前缀布局保持稳定。
final class AgentTimelineExtentDescriptorFactory {
  /// 创建工厂。
  AgentTimelineExtentDescriptorFactory();

  List<IdeVirtualItemDescriptor>? _lastDescriptors;

  /// 诊断：describeAll 复用上一帧 descriptor 实例的次数。
  int debugReusedDescriptorCount = 0;

  /// 诊断：实际新建 descriptor 的次数。
  int debugBuiltDescriptorCount = 0;

  /// 清除复用缓存（会话切换时调用）。
  void clearCache() {
    _lastDescriptors = null;
  }

  /// 将视口 item 列表转为 descriptor 序列。
  ///
  /// 当与上一帧相比仅尾部 revision 变化时，前缀项返回**同一实例**，
  /// 便于 [IdeVirtualListController.setItems] 短路与减少分配。
  List<IdeVirtualItemDescriptor> describeAll(
    List<AgentTimelineViewportItem> items, {
    required AgentTimelineExpansionLookup expansion,
    required AgentTimelineLayoutContext layoutContext,
  }) {
    final previous = _lastDescriptors;
    final next = List<IdeVirtualItemDescriptor>.generate(items.length, (index) {
      final built = describe(
        items[index],
        previousItem: index > 0 ? items[index - 1] : null,
        expansion: expansion,
        layoutContext: layoutContext,
      );
      if (previous != null &&
          index < previous.length &&
          _descriptorFingerprintEquals(previous[index], built)) {
        debugReusedDescriptorCount += 1;
        return previous[index];
      }
      debugBuiltDescriptorCount += 1;
      return built;
    }, growable: false);
    _lastDescriptors = next;
    return next;
  }

  /// 描述单个 viewport item。
  IdeVirtualItemDescriptor describe(
    AgentTimelineViewportItem item, {
    AgentTimelineViewportItem? previousItem,
    required AgentTimelineExpansionLookup expansion,
    required AgentTimelineLayoutContext layoutContext,
  }) {
    final precededByOperationGroup = _isPrecededByOperationGroup(previousItem);
    final kind = _kindOf(item);
    final revision = _layoutRevision(
      item,
      expansion,
      precededByOperationGroup: precededByOperationGroup,
    );
    final estimated = _estimateExtent(
      item,
      kind: kind,
      crossAxisExtent: layoutContext.crossAxisExtent,
      textScale: layoutContext.textScale,
      expansion: expansion,
      precededByOperationGroup: precededByOperationGroup,
    );
    return IdeVirtualItemDescriptor(
      id: item.id,
      kind: kind,
      layoutRevision: revision,
      estimatedExtent: estimated,
    );
  }

  String _kindOf(AgentTimelineViewportItem item) {
    return switch (item) {
      AgentLiveActivityViewportItem() => AgentTimelineExtentKinds.liveActivity,
      AgentTurnFooterViewportItem() => AgentTimelineExtentKinds.turnFooter,
      AgentBlockViewportItem(:final block) => switch (block) {
        AgentTimelineCommandGroupRenderBlock() =>
          AgentTimelineExtentKinds.commandGroup,
        AgentTimelineFileEditGroupRenderBlock() =>
          AgentTimelineExtentKinds.fileEditGroup,
        AgentTimelineEntryRenderBlock(:final entry) => switch (entry) {
          AgentMessageTimelineEntry(:final message) => _kindForMessage(message),
          AgentToolTimelineEntry() => AgentTimelineExtentKinds.toolCard,
          AgentPermissionTimelineEntry() ||
          AgentQuestionTimelineEntry() => AgentTimelineExtentKinds.toolCard,
          // 审批卡在流内展示完整计划正文，不能按 tool card 的固定高度估算。
          AgentPlanApprovalTimelineEntry() =>
            AgentTimelineExtentKinds.planInteraction,
          AgentHistoryEventTimelineEntry() => AgentTimelineExtentKinds.system,
          AgentTurnDiffTimelineEntry() =>
            AgentTimelineExtentKinds.fileEditGroup,
        },
      },
    };
  }

  String _kindForMessage(AgentConversationMessage message) {
    if (message.isPlan) {
      return AgentTimelineExtentKinds.plan;
    }
    return switch (message.role) {
      AgentMessageRole.user => AgentTimelineExtentKinds.userMessage,
      AgentMessageRole.agent => AgentTimelineExtentKinds.agentMarkdown,
      AgentMessageRole.system => AgentTimelineExtentKinds.system,
    };
  }

  /// 布局失效指纹。
  ///
  /// 流式更新只让**变化 entry** 的 revision 改变，
  /// 禁止用整 turn 的 [AgentConversationTurnGroup.renderRevision] 绑死所有 block，
  /// 否则 live turn 内每个字符都会把 sibling tool card 标成 measurement stale。
  Object _layoutRevision(
    AgentTimelineViewportItem item,
    AgentTimelineExpansionLookup expansion, {
    bool precededByOperationGroup = false,
  }) {
    return switch (item) {
      AgentLiveActivityViewportItem(:final turn) => Object.hash(
        'live-activity',
        turn.id,
        turn.metaRevision,
        turn.status,
      ),
      AgentTurnFooterViewportItem(:final turn) => Object.hash(
        'footer',
        turn.id,
        turn.metaRevision,
        turn.status,
        turn.tokenUsage?.totalTokens,
        turn.duration?.inMilliseconds,
        turn.modelConfig?.modelId,
      ),
      AgentBlockViewportItem(:final turn, :final block) => Object.hash(
        'block',
        turn.id,
        block.id,
        _blockContentRevision(block),
        _blockExpansionFingerprint(block, expansion),
        // 相邻操作组折叠 top 外间距会影响实测高度。
        isAgentTimelineOperationGroupBlock(block)
            ? precededByOperationGroup
            : null,
      ),
    };
  }

  /// 单个 render block 的内容指纹（不含 turn 级 renderRevision）。
  Object _blockContentRevision(AgentTimelineRenderBlock block) {
    return switch (block) {
      AgentTimelineCommandGroupRenderBlock(:final group) => Object.hashAll([
        for (final item in group.items)
          Object.hash(
            item.id,
            item.kind,
            item.title,
            _entryContentRevision(item.entry),
          ),
      ]),
      AgentTimelineFileEditGroupRenderBlock(:final group) => Object.hashAll([
        for (final item in group.items)
          Object.hash(
            item.id,
            item.filePath,
            item.title,
            item.addedLines,
            item.removedLines,
            item.details,
          ),
      ]),
      AgentTimelineEntryRenderBlock(:final entry) => _entryContentRevision(
        entry,
      ),
    };
  }

  Object _entryContentRevision(AgentTimelineEntry entry) {
    return switch (entry) {
      AgentMessageTimelineEntry(:final message) => Object.hash(
        message.id,
        message.kind,
        message.phase,
        message.status,
        message.role,
        message.text.length,
        message.text.hashCode,
      ),
      AgentToolTimelineEntry(:final toolCall) => Object.hash(
        toolCall.id,
        toolCall.kind,
        toolCall.status,
        toolCall.title,
        toolCall.content?.length,
        toolCall.content?.hashCode,
        toolCall.duration?.inMilliseconds,
      ),
      AgentPermissionTimelineEntry(:final request) => Object.hash(
        request.id,
        request.title,
        request.kind,
        request.command,
        request.description,
      ),
      AgentQuestionTimelineEntry(:final request) => Object.hash(
        request.id,
        request.title,
        request.description,
        request.questions.length,
      ),
      AgentPlanApprovalTimelineEntry(:final request) => Object.hash(
        request.id,
        request.title,
        request.markdown.length,
        request.markdown.hashCode,
        request.todos.length,
      ),
      AgentHistoryEventTimelineEntry(:final event) => Object.hash(
        event.id,
        event.kind,
        event.title,
        event.description,
        event.content?.length,
      ),
      AgentTurnDiffTimelineEntry(:final turnId, :final diff) => Object.hash(
        turnId,
        diff.length,
        diff.hashCode,
      ),
    };
  }

  Object _blockExpansionFingerprint(
    AgentTimelineRenderBlock block,
    AgentTimelineExpansionLookup expansion,
  ) {
    return switch (block) {
      AgentTimelineCommandGroupRenderBlock(:final group) =>
        expansion.isCommandGroupExpanded(group.id),
      AgentTimelineFileEditGroupRenderBlock(:final group) => Object.hashAll([
        for (final item in group.items)
          Object.hash(item.id, expansion.isFileEditItemExpanded(item.id)),
      ]),
      // plan 消息在折叠卡与交互卡之间切换时高度差异巨大，必须让缓存测量失效。
      AgentTimelineEntryRenderBlock(:final entry) =>
        entry is AgentMessageTimelineEntry && entry.message.isPlan
            ? expansion.isPlanMessageInteractive(entry.message.id)
            : 0,
    };
  }

  double _estimateExtent(
    AgentTimelineViewportItem item, {
    required String kind,
    required double crossAxisExtent,
    required double textScale,
    required AgentTimelineExpansionLookup expansion,
    bool precededByOperationGroup = false,
  }) {
    final width = crossAxisExtent.isFinite && crossAxisExtent > 0
        ? crossAxisExtent
        : 720.0;
    final scale = textScale.isFinite && textScale > 0 ? textScale : 1.0;
    final lineHeight = 18.0 * scale;

    return switch (item) {
      AgentLiveActivityViewportItem() => 36 * scale,
      AgentTurnFooterViewportItem() => 28 * scale,
      AgentBlockViewportItem(:final block) => switch (block) {
        AgentTimelineCommandGroupRenderBlock(:final group) =>
          _estimateCommandGroup(
            group,
            expansion,
            scale,
            precededByOperationGroup: precededByOperationGroup,
          ),
        AgentTimelineFileEditGroupRenderBlock(:final group) =>
          _estimateFileEditGroup(
            group,
            expansion,
            scale,
            precededByOperationGroup: precededByOperationGroup,
          ),
        AgentTimelineEntryRenderBlock(:final entry) => _estimateEntry(
          entry,
          kind: kind,
          width: width,
          lineHeight: lineHeight,
          scale: scale,
          expansion: expansion,
        ),
      },
    };
  }

  double _estimateCommandGroup(
    AgentTimelineCommandGroup group,
    AgentTimelineExpansionLookup expansion,
    double scale, {
    bool precededByOperationGroup = false,
  }) {
    // 内容区约 30；外间距上下各 10，紧挨上一操作组时省略 top。
    final content = expansion.isCommandGroupExpanded(group.id)
        ? 30 + group.items.length * 28
        : 30;
    final top = precededByOperationGroup ? 0.0 : 10.0;
    const bottom = 10.0;
    return (content + top + bottom) * scale;
  }

  double _estimateFileEditGroup(
    AgentTimelineFileEditGroup group,
    AgentTimelineExpansionLookup expansion,
    double scale, {
    bool precededByOperationGroup = false,
  }) {
    // 内容区：折叠头约 30 + 各文件行；外间距与命令集相同规则。
    var content = 30.0;
    for (final item in group.items) {
      if (expansion.isFileEditItemExpanded(item.id)) {
        content += 120;
      } else {
        content += 28;
      }
    }
    final top = precededByOperationGroup ? 0.0 : 10.0;
    const bottom = 10.0;
    return (content + top + bottom) * scale;
  }

  double _estimateEntry(
    AgentTimelineEntry entry, {
    required String kind,
    required double width,
    required double lineHeight,
    required double scale,
    required AgentTimelineExpansionLookup expansion,
  }) {
    if (entry is AgentMessageTimelineEntry) {
      return _estimateMessage(
        entry.message,
        kind: kind,
        width: width,
        lineHeight: lineHeight,
        scale: scale,
        expansion: expansion,
      );
    }
    if (entry is AgentToolTimelineEntry) {
      return 56 * scale;
    }
    if (entry is AgentTurnDiffTimelineEntry) {
      return 80 * scale;
    }
    if (entry is AgentPlanApprovalTimelineEntry) {
      // 审批卡在流内始终是交互态：正文全文 + 底部输入与动作栏。
      return math.max(
        24.0,
        _estimateMarkdownExtent(
              entry.request.markdown,
              width: width,
              lineHeight: lineHeight,
              scale: scale,
            ) +
            _planInteractionChromeExtent(scale),
      );
    }
    return 48 * scale;
  }

  double _estimateMessage(
    AgentConversationMessage message, {
    required String kind,
    required double width,
    required double lineHeight,
    required double scale,
    required AgentTimelineExpansionLookup expansion,
  }) {
    final text = message.text;
    final isInteractivePlan =
        message.isPlan && expansion.isPlanMessageInteractive(message.id);
    if (text.trim().isEmpty) {
      return isInteractivePlan
          ? 32 * scale + _planInteractionChromeExtent(scale)
          : 32 * scale;
    }

    final padding = 24 * scale;
    final base = kind == AgentTimelineExtentKinds.agentMarkdown
        ? 200 * scale
        : kind == AgentTimelineExtentKinds.plan
        ? 120 * scale
        : 48 * scale;

    final content =
        padding +
        _estimateMarkdownExtent(
          text,
          width: width,
          lineHeight: lineHeight,
          scale: scale,
        );
    // 冷启动基线：取 content 与 kind 默认的较大者。不要截断长消息估算，
    // 否则单项超过旧上限后会在滚动帧内产生巨大的同步 measurement delta。
    final estimated = math.max(base * 0.5, content);
    // 交互态计划卡额外挂着输入框与动作栏，不加上会严重低估。
    final chrome = isInteractivePlan
        ? _planInteractionChromeExtent(scale)
        : 0.0;
    return math.max(24.0, estimated + chrome);
  }

  /// 计划交互卡底部输入框 + 动作栏 + 分隔线的固定高度。
  double _planInteractionChromeExtent(double scale) => 120 * scale;

  /// 按源行逐行累加折行，估算一段 Markdown 的渲染高度。
  double _estimateMarkdownExtent(
    String text, {
    required double width,
    required double lineHeight,
    required double scale,
  }) {
    // 全文渲染：历史与 live 均按完整内容估算高度，禁止折叠预览截断。
    final charsPerLine = math.max(24, (width / (7.5 * scale)).floor());
    var visualLines = 0;
    var blockSpacingLines = 0.0;
    var insideFence = false;
    for (final sourceLine in text.split('\n')) {
      final trimmed = sourceLine.trim();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        insideFence = !insideFence;
        visualLines += 1;
        blockSpacingLines += 0.5;
        continue;
      }

      // 必须逐源行累加折行；按全文字符数与显式行数取 max 会严重低估
      // “多行且每行都需要折行”的长 Markdown。
      final lineLength = trimmed.runes.length;
      final effectiveCharsPerLine = insideFence
          ? math.max(20, (charsPerLine * 0.9).floor())
          : charsPerLine;
      visualLines += math.max(1, (lineLength / effectiveCharsPerLine).ceil());

      if (trimmed.isEmpty) {
        blockSpacingLines += 0.45;
      } else if (!insideFence && trimmed.startsWith('#')) {
        blockSpacingLines += 0.7;
      } else if (!insideFence &&
          (trimmed.startsWith('- ') ||
              trimmed.startsWith('* ') ||
              trimmed.startsWith('> '))) {
        blockSpacingLines += 0.15;
      }
    }

    return (visualLines + blockSpacingLines) * lineHeight;
  }

  static bool _descriptorFingerprintEquals(
    IdeVirtualItemDescriptor a,
    IdeVirtualItemDescriptor b,
  ) {
    return a.id == b.id &&
        a.kind == b.kind &&
        a.layoutRevision == b.layoutRevision &&
        a.estimatedExtent == b.estimatedExtent;
  }
}

/// 上一视口项是否为操作组（命令集 / 文件编辑组）。
bool _isPrecededByOperationGroup(AgentTimelineViewportItem? item) {
  return item is AgentBlockViewportItem &&
      isAgentTimelineOperationGroupBlock(item.block);
}
