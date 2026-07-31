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
});

/// Agent item kind 常量（仅用于估算，不参与业务分支）。
abstract final class AgentTimelineExtentKinds {
  static const userMessage = 'userMessage';
  static const agentMarkdown = 'agentMarkdown';
  static const plan = 'plan';
  static const toolCard = 'toolCard';
  static const commandGroup = 'commandGroup';
  static const fileEditGroup = 'fileEditGroup';
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
    required AgentTimelineExpansionLookup expansion,
    required AgentTimelineLayoutContext layoutContext,
  }) {
    final kind = _kindOf(item);
    final revision = _layoutRevision(item, expansion);
    final estimated = _estimateExtent(
      item,
      kind: kind,
      crossAxisExtent: layoutContext.crossAxisExtent,
      textScale: layoutContext.textScale,
      expansion: expansion,
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
          AgentQuestionTimelineEntry() ||
          AgentPlanApprovalTimelineEntry() => AgentTimelineExtentKinds.toolCard,
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
    AgentTimelineExpansionLookup expansion,
  ) {
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
      AgentTimelineEntryRenderBlock() => 0,
    };
  }

  double _estimateExtent(
    AgentTimelineViewportItem item, {
    required String kind,
    required double crossAxisExtent,
    required double textScale,
    required AgentTimelineExpansionLookup expansion,
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
          _estimateCommandGroup(group, expansion, scale),
        AgentTimelineFileEditGroupRenderBlock(:final group) =>
          _estimateFileEditGroup(group, expansion, scale),
        AgentTimelineEntryRenderBlock(:final entry) => _estimateEntry(
          entry,
          kind: kind,
          width: width,
          lineHeight: lineHeight,
          scale: scale,
        ),
      },
    };
  }

  double _estimateCommandGroup(
    AgentTimelineCommandGroup group,
    AgentTimelineExpansionLookup expansion,
    double scale,
  ) {
    final expanded = expansion.isCommandGroupExpanded(group.id);
    final header = 40 * scale;
    if (!expanded) {
      return header;
    }
    return header + group.items.length * 28 * scale;
  }

  double _estimateFileEditGroup(
    AgentTimelineFileEditGroup group,
    AgentTimelineExpansionLookup expansion,
    double scale,
  ) {
    final header = 40 * scale;
    var body = 0.0;
    for (final item in group.items) {
      if (expansion.isFileEditItemExpanded(item.id)) {
        body += 120 * scale;
      } else {
        body += 28 * scale;
      }
    }
    return header + body;
  }

  double _estimateEntry(
    AgentTimelineEntry entry, {
    required String kind,
    required double width,
    required double lineHeight,
    required double scale,
  }) {
    if (entry is AgentMessageTimelineEntry) {
      return _estimateMessage(
        entry.message,
        kind: kind,
        width: width,
        lineHeight: lineHeight,
        scale: scale,
      );
    }
    if (entry is AgentToolTimelineEntry) {
      return 56 * scale;
    }
    if (entry is AgentTurnDiffTimelineEntry) {
      return 80 * scale;
    }
    return 48 * scale;
  }

  double _estimateMessage(
    AgentConversationMessage message, {
    required String kind,
    required double width,
    required double lineHeight,
    required double scale,
  }) {
    final text = message.text;
    if (text.trim().isEmpty) {
      return 32 * scale;
    }

    // 全文渲染：历史与 live 均按完整内容估算高度，禁止折叠预览截断。
    final charsPerLine = math.max(24, (width / (7.5 * scale)).floor());
    final explicitLines = '\n'.allMatches(text).length + 1;
    final nonWs = text.replaceAll(RegExp(r'\s+'), '').length;
    final wrapped = (nonWs / charsPerLine).ceil();
    final fencePenalty = '```'.allMatches(text).length * 2;
    final visualLines = math.max(explicitLines, wrapped) + fencePenalty;

    final padding = 24 * scale;
    final base = kind == AgentTimelineExtentKinds.agentMarkdown
        ? 200 * scale
        : kind == AgentTimelineExtentKinds.plan
        ? 120 * scale
        : 48 * scale;

    final content = padding + visualLines * lineHeight;
    // 冷启动基线：取 content 与 kind 默认的较大者，并做合理 clamp。
    final estimated = math.max(base * 0.5, content);
    return estimated.clamp(24.0, 4000.0);
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
