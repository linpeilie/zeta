import 'dart:convert';

import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_file_change_projection.dart';
import 'package:zeta/src/features/agent/presentation/agent_file_change_projection_cache.dart';

/// Agent 时间线在 UI 层的渲染块。
///
/// 原始时间线条目保持不变；这里仅在渲染前把连续操作项折叠成命令集或文件编辑组。
sealed class AgentTimelineRenderBlock {
  const AgentTimelineRenderBlock({required this.id});

  /// 渲染块的稳定 id。
  final String id;
}

/// 直接透传的单个时间线条目。
class AgentTimelineEntryRenderBlock extends AgentTimelineRenderBlock {
  AgentTimelineEntryRenderBlock({required this.entry}) : super(id: entry.id);

  /// 原始时间线条目。
  final AgentTimelineEntry entry;
}

/// 由多个连续非编辑操作组成的命令集。
class AgentTimelineCommandGroupRenderBlock extends AgentTimelineRenderBlock {
  AgentTimelineCommandGroupRenderBlock({required this.group})
    : super(id: group.id);

  /// 命令集摘要。
  final AgentTimelineCommandGroup group;
}

/// 由多个连续编辑操作组成的文件编辑组。
class AgentTimelineFileEditGroupRenderBlock extends AgentTimelineRenderBlock {
  AgentTimelineFileEditGroupRenderBlock({required this.group})
    : super(id: group.id);

  /// 文件编辑组摘要。
  final AgentTimelineFileEditGroup group;
}

/// 命令集与文件编辑组在布局上同属「操作组」：相邻时折叠 top 外间距。
///
/// 领域模型仍是两类 block；此谓词只服务间距 / 高度估计。
bool isAgentTimelineOperationGroupBlock(AgentTimelineRenderBlock block) {
  return block is AgentTimelineCommandGroupRenderBlock ||
      block is AgentTimelineFileEditGroupRenderBlock;
}

/// 命令集本身。
class AgentTimelineCommandGroup {
  const AgentTimelineCommandGroup({required this.id, required this.items});

  /// 命令集稳定 id。
  final String id;

  /// 组内按原顺序排列的摘要项。
  final List<AgentTimelineCommandGroupItem> items;
}

/// 文件编辑组本身。
class AgentTimelineFileEditGroup {
  const AgentTimelineFileEditGroup({
    required this.id,
    required this.items,
    this.isTurnFallback = false,
  });

  /// 文件编辑组稳定 id。
  final String id;

  /// 组内按原顺序排列的文件编辑项。
  final List<AgentTimelineFileEditItem> items;

  /// 是否为回合级 live-only 降级汇总。
  final bool isTurnFallback;
}

/// 命令集中的单条摘要项。
class AgentTimelineCommandGroupItem {
  const AgentTimelineCommandGroupItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.entry,
  });

  /// 摘要项稳定 id。
  final String id;

  /// 归一化后的工具类型，用于图标和汇总展示。
  final AgentToolKind kind;

  /// 原始标题。
  final String title;

  /// 对应的原始时间线条目。
  final AgentTimelineEntry entry;
}

/// 文件编辑组中的单个文件项。
class AgentTimelineFileEditItem {
  const AgentTimelineFileEditItem({
    required this.id,
    required this.title,
    required this.projection,
    this.status,
  });

  /// 文件项稳定 id。
  final String id;

  /// UI 标题，默认与文件路径一致。
  final String title;

  /// owner + revision + change id 已缓存的中立展示投影。
  final AgentFileChangeItemProjection projection;

  /// tool owner 的生命周期状态；turn fallback 没有 tool 状态。
  final AgentToolStatus? status;

  String get ownerEntryId => projection.ownerEntryId;
  String get filePath => projection.path;
  int? get addedLines => projection.statistics?.addedLines;
  int? get removedLines => projection.statistics?.removedLines;

  /// 是否可展开查看详情。
  bool get hasDetails => projection.detail != null;
}

enum _AgentTimelineOperationGroupKind { command, fileEdit }

/// 把单个 turn 的时间线条目规约成 UI 渲染块。
///
/// - 连续 1 条及以上的非编辑操作会合并为命令集
/// - 连续 1 条及以上的编辑操作会合并为文件编辑组
/// - 思考条目仅用于驱动实时活动状态，不生成可见渲染块
/// - 其他条目会打断分组并按原样单独渲染
List<AgentTimelineRenderBlock> buildAgentTimelineRenderBlocks({
  required String turnId,
  required List<AgentTimelineEntry> entries,
  AgentFileChangeProjectionCache? fileChangeProjectionCache,
}) {
  final fileChangeCache =
      fileChangeProjectionCache ?? AgentFileChangeProjectionCache();
  final blocks = <AgentTimelineRenderBlock>[];
  final pendingOperations = <_PendingOperation>[];
  final seenEntryIds = <String>{};
  _AgentTimelineOperationGroupKind? pendingKind;

  void flushPendingOperations() {
    if (pendingOperations.isEmpty || pendingKind == null) {
      pendingOperations.clear();
      pendingKind = null;
      return;
    }

    switch (pendingKind!) {
      case _AgentTimelineOperationGroupKind.command:
        final items = List<AgentTimelineCommandGroupItem>.unmodifiable(
          pendingOperations
              .map((operation) => operation.commandItem)
              .whereType<AgentTimelineCommandGroupItem>(),
        );
        if (items.isNotEmpty) {
          blocks.add(
            AgentTimelineCommandGroupRenderBlock(
              group: AgentTimelineCommandGroup(
                id: 'command-group-$turnId-${items.first.entry.id}',
                items: items,
              ),
            ),
          );
        }
      case _AgentTimelineOperationGroupKind.fileEdit:
        final items = List<AgentTimelineFileEditItem>.unmodifiable(
          pendingOperations
              .expand((operation) => operation.fileEditItems)
              .toList(),
        );
        if (items.isNotEmpty) {
          blocks.add(
            AgentTimelineFileEditGroupRenderBlock(
              group: AgentTimelineFileEditGroup(
                id: 'file-edit-group-$turnId-${items.first.ownerEntryId}',
                items: items,
              ),
            ),
          );
        }
    }

    pendingOperations.clear();
    pendingKind = null;
  }

  for (final entry in entries) {
    if (_shouldSkipTimelineEntry(entry)) {
      continue;
    }
    // 同 id 条目只渲染一次，避免 Flutter Duplicate keys。
    if (!seenEntryIds.add(entry.id)) {
      continue;
    }

    final operation = _pendingOperationFromEntry(
      entry,
      fileChangeCache: fileChangeCache,
    );
    if (operation == null) {
      // 回合级 typed fallback 不与相邻 tool owner 合并。
      if (entry is AgentTurnFileChangesTimelineEntry) {
        flushPendingOperations();
        final items = _fileEditItemsFromSnapshot(
          ownerEntryId: entry.id,
          snapshot: entry.snapshot,
          cache: fileChangeCache,
        );
        if (items.isNotEmpty) {
          blocks.add(
            AgentTimelineFileEditGroupRenderBlock(
              group: AgentTimelineFileEditGroup(
                id: 'turn-file-changes-group-$turnId',
                items: items,
                isTurnFallback: true,
              ),
            ),
          );
        }
        continue;
      }
      flushPendingOperations();
      blocks.add(AgentTimelineEntryRenderBlock(entry: entry));
      continue;
    }

    if (pendingKind != null && pendingKind != operation.groupKind) {
      flushPendingOperations();
    }

    pendingKind = operation.groupKind;
    pendingOperations.add(operation);
  }

  flushPendingOperations();
  return List<AgentTimelineRenderBlock>.unmodifiable(blocks);
}

class _PendingOperation {
  const _PendingOperation.command({required this.commandItem})
    : groupKind = _AgentTimelineOperationGroupKind.command,
      fileEditItems = const <AgentTimelineFileEditItem>[];

  const _PendingOperation.fileEdit({required this.fileEditItems})
    : groupKind = _AgentTimelineOperationGroupKind.fileEdit,
      commandItem = null;

  final _AgentTimelineOperationGroupKind groupKind;
  final AgentTimelineCommandGroupItem? commandItem;
  final List<AgentTimelineFileEditItem> fileEditItems;
}

_PendingOperation? _pendingOperationFromEntry(
  AgentTimelineEntry entry, {
  required AgentFileChangeProjectionCache fileChangeCache,
}) {
  return switch (entry) {
    AgentToolTimelineEntry(:final toolCall)
        when toolCall.fileChanges != null &&
            toolCall.fileChanges!.changes.isNotEmpty =>
      _PendingOperation.fileEdit(
        fileEditItems: _fileEditItemsFromSnapshot(
          ownerEntryId: entry.id,
          snapshot: toolCall.fileChanges!,
          cache: fileChangeCache,
          status: toolCall.status,
        ),
      ),
    AgentToolTimelineEntry(:final toolCall) => _PendingOperation.command(
      commandItem: AgentTimelineCommandGroupItem(
        id: entry.id,
        kind: toolCall.kind,
        title: toolCall.displayTitle,
        entry: entry,
      ),
    ),
    AgentHistoryEventTimelineEntry(:final event)
        when event.kind == AgentHistoryEventKind.search =>
      _PendingOperation.command(
        commandItem: AgentTimelineCommandGroupItem(
          id: entry.id,
          kind: AgentToolKind.search,
          title: _searchEntryTitle(event),
          entry: entry,
        ),
      ),
    _ => null,
  };
}

List<AgentTimelineFileEditItem> _fileEditItemsFromSnapshot({
  required String ownerEntryId,
  required AgentFileChangeSnapshot snapshot,
  required AgentFileChangeProjectionCache cache,
  AgentToolStatus? status,
}) {
  final projection = cache.resolve(
    ownerEntryId: ownerEntryId,
    snapshot: snapshot,
  );
  return <AgentTimelineFileEditItem>[
    for (final item in projection.items)
      AgentTimelineFileEditItem(
        id: 'file-edit-$ownerEntryId-${item.changeId}',
        title: _fileEditItemTitle(item.path),
        projection: item,
        status: status,
      ),
  ];
}

String _fileEditItemTitle(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return filePath;
  }
  return parts.last;
}

bool _shouldSkipTimelineEntry(AgentTimelineEntry entry) {
  return switch (entry) {
    AgentToolTimelineEntry(:final toolCall)
        when toolCall.kind == AgentToolKind.think =>
      true,
    AgentHistoryEventTimelineEntry(:final event)
        when event.kind == AgentHistoryEventKind.search =>
      _shouldSkipSearchEvent(event),
    _ => false,
  };
}

bool _shouldSkipSearchEvent(AgentHistoryEventEntry event) {
  if (event.title != 'Web search') {
    return false;
  }
  return _searchEventDetail(event) == null;
}

String _searchEntryTitle(AgentHistoryEventEntry event) {
  if (event.title != 'Web search') {
    return event.title;
  }
  final detail = _searchEventDetail(event);
  if (detail == null) {
    return event.title;
  }
  return '${event.title} · $detail';
}

String? _searchEventDetail(AgentHistoryEventEntry event) {
  return _singleLinePreview(event.description) ??
      _singleLinePreview(event.content);
}

String? _singleLinePreview(String? text) {
  if (text == null) {
    return null;
  }

  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}
