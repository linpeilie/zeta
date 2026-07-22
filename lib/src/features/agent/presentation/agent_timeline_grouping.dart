import 'dart:convert';

import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

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
  const AgentTimelineFileEditGroup({required this.id, required this.items});

  /// 文件编辑组稳定 id。
  final String id;

  /// 组内按原顺序排列的文件编辑项。
  final List<AgentTimelineFileEditItem> items;
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
    required this.toolCallId,
    required this.filePath,
    required this.title,
    this.addedLines,
    this.removedLines,
    this.details,
  });

  /// 文件项稳定 id。
  final String id;

  /// 来源工具调用 id。
  final String toolCallId;

  /// 文件路径。
  final String filePath;

  /// UI 标题，默认与文件路径一致。
  final String title;

  /// 新增行数。
  final int? addedLines;

  /// 删除行数。
  final int? removedLines;

  /// 当前文件的标准 unified diff；为空表示不可展开。
  final String? details;

  /// 是否可展开查看详情。
  bool get hasDetails => details != null && details!.trim().isNotEmpty;
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
}) {
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
                id: 'file-edit-group-$turnId-${items.first.toolCallId}',
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

    final operation = _pendingOperationFromEntry(entry);
    if (operation == null) {
      // 回合级聚合 diff 直接渲染为文件编辑组，复用现有 diff 卡片。
      if (entry is AgentTurnDiffTimelineEntry) {
        flushPendingOperations();
        final items = _fileEditItemsFromUnifiedDiff(
          toolCallId: entry.id,
          unifiedDiff: entry.diff,
        );
        if (items.isNotEmpty) {
          blocks.add(
            AgentTimelineFileEditGroupRenderBlock(
              group: AgentTimelineFileEditGroup(
                id: 'turn-diff-group-$turnId',
                items: items,
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

_PendingOperation? _pendingOperationFromEntry(AgentTimelineEntry entry) {
  return switch (entry) {
    AgentToolTimelineEntry(:final toolCall)
        when toolCall.kind == AgentToolKind.edit =>
      _PendingOperation.fileEdit(
        fileEditItems: _fileEditItemsFromToolCall(toolCall),
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

List<AgentTimelineFileEditItem> _fileEditItemsFromToolCall(
  AgentToolCall toolCall,
) {
  final fileChanges = _fileEditChangesFromToolCall(toolCall);
  if (fileChanges.isNotEmpty) {
    return <AgentTimelineFileEditItem>[
      for (final change in fileChanges)
        AgentTimelineFileEditItem(
          id: 'file-edit-${toolCall.id}-${change.filePath}',
          toolCallId: toolCall.id,
          filePath: change.filePath,
          title: _fileEditItemTitle(change.filePath),
          addedLines: change.addedLines,
          removedLines: change.removedLines,
          details: change.unifiedDiff,
        ),
    ];
  }

  final filePaths = toolCall.locations.isNotEmpty
      ? toolCall.locations
      : _fallbackFilePathsFromToolCall(toolCall);
  if (filePaths.isEmpty) {
    final fallbackTitle = toolCall.displayTitle;
    return <AgentTimelineFileEditItem>[
      AgentTimelineFileEditItem(
        id: 'file-edit-${toolCall.id}',
        toolCallId: toolCall.id,
        filePath: fallbackTitle,
        title: _fileEditItemTitle(fallbackTitle),
      ),
    ];
  }

  return <AgentTimelineFileEditItem>[
    for (final filePath in filePaths)
      AgentTimelineFileEditItem(
        id: 'file-edit-${toolCall.id}-$filePath',
        toolCallId: toolCall.id,
        filePath: filePath,
        title: _fileEditItemTitle(filePath),
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

List<_FileEditChange> _fileEditChangesFromToolCall(AgentToolCall toolCall) {
  final changes = toolCall.rawOutput['changes'];
  if (changes is! Map<Object?, Object?>) {
    return const <_FileEditChange>[];
  }

  final fileChanges = <_FileEditChange>[];
  for (final entry in changes.entries) {
    final filePath = entry.key;
    if (filePath is! String || filePath.isEmpty) {
      continue;
    }

    final unifiedDiff = _trimmedStringFromValue(
      _mapValue(entry.value)['unified_diff'],
    );
    final lineStats = _unifiedDiffLineStats(unifiedDiff);
    fileChanges.add(
      _FileEditChange(
        filePath: filePath,
        unifiedDiff: unifiedDiff,
        addedLines: lineStats?.addedLines,
        removedLines: lineStats?.removedLines,
      ),
    );
  }
  return List<_FileEditChange>.unmodifiable(fileChanges);
}

/// 将回合级聚合 unified diff 拆成按文件的编辑项。
List<AgentTimelineFileEditItem> _fileEditItemsFromUnifiedDiff({
  required String toolCallId,
  required String unifiedDiff,
}) {
  final changes = _fileEditChangesFromUnifiedDiff(unifiedDiff);
  if (changes.isEmpty) {
    final lineStats = _unifiedDiffLineStats(unifiedDiff);
    return <AgentTimelineFileEditItem>[
      AgentTimelineFileEditItem(
        id: 'turn-diff-$toolCallId',
        toolCallId: toolCallId,
        filePath: '本回合改动',
        title: '本回合改动',
        addedLines: lineStats?.addedLines,
        removedLines: lineStats?.removedLines,
        details: unifiedDiff.trim().isEmpty ? null : unifiedDiff,
      ),
    ];
  }

  return <AgentTimelineFileEditItem>[
    for (final change in changes)
      AgentTimelineFileEditItem(
        id: 'turn-diff-$toolCallId-${change.filePath}',
        toolCallId: toolCallId,
        filePath: change.filePath,
        title: _fileEditItemTitle(change.filePath),
        addedLines: change.addedLines,
        removedLines: change.removedLines,
        details: change.unifiedDiff,
      ),
  ];
}

/// 按 `diff --git` / `+++` 头拆分多文件 unified diff。
List<_FileEditChange> _fileEditChangesFromUnifiedDiff(String unifiedDiff) {
  final lines = const LineSplitter().convert(unifiedDiff);
  if (lines.isEmpty) {
    return const <_FileEditChange>[];
  }

  final fileChanges = <_FileEditChange>[];
  String? currentPath;
  final currentLines = <String>[];

  void flush() {
    final path = currentPath;
    if (path == null || currentLines.isEmpty) {
      currentLines.clear();
      return;
    }
    final chunk = currentLines.join('\n');
    final lineStats = _unifiedDiffLineStats(chunk);
    fileChanges.add(
      _FileEditChange(
        filePath: path,
        unifiedDiff: chunk,
        addedLines: lineStats?.addedLines,
        removedLines: lineStats?.removedLines,
      ),
    );
    currentLines.clear();
  }

  for (final line in lines) {
    final gitPath = _pathFromDiffGitHeader(line);
    if (gitPath != null) {
      flush();
      currentPath = gitPath;
      currentLines.add(line);
      continue;
    }

    final plusPath = _pathFromDiffPlusHeader(line);
    if (plusPath != null && currentPath == null) {
      currentPath = plusPath;
    }
    currentLines.add(line);
  }
  flush();

  return List<_FileEditChange>.unmodifiable(fileChanges);
}

String? _pathFromDiffGitHeader(String line) {
  // diff --git a/path b/path
  if (!line.startsWith('diff --git ')) {
    return null;
  }
  final parts = line.substring('diff --git '.length).split(' ');
  if (parts.length < 2) {
    return null;
  }
  final bPath = parts.last;
  if (bPath.startsWith('b/')) {
    return bPath.substring(2);
  }
  return bPath;
}

String? _pathFromDiffPlusHeader(String line) {
  // +++ b/path 或 +++ path
  if (!line.startsWith('+++ ')) {
    return null;
  }
  var path = line.substring(4).trim();
  if (path == '/dev/null') {
    return null;
  }
  // 去掉可选的时间戳后缀。
  final tab = path.indexOf('\t');
  if (tab != -1) {
    path = path.substring(0, tab);
  }
  if (path.startsWith('b/')) {
    return path.substring(2);
  }
  return path;
}

List<String> _fallbackFilePathsFromToolCall(AgentToolCall toolCall) {
  final raw = <String>{
    ..._pathsFromValue(toolCall.raw['changes']),
    ..._pathsFromValue(toolCall.rawOutput['changes']),
    ..._pathsFromValue(toolCall.rawInput['changes']),
  };
  return raw.where((path) => path.isNotEmpty).toList();
}

Set<String> _pathsFromValue(Object? value) {
  final result = <String>{};
  if (value is List<Object?>) {
    for (final item in value) {
      if (item is Map) {
        final path = item['path'];
        if (path is String && path.isNotEmpty) {
          result.add(path);
        }
      }
    }
    return result;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String && key.isNotEmpty) {
        result.add(key);
      }
    }
  }
  return result;
}

String? _trimmedStringFromValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

Map<String, Object?> _mapValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return const <String, Object?>{};
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

class _FileEditChange {
  const _FileEditChange({
    required this.filePath,
    required this.unifiedDiff,
    this.addedLines,
    this.removedLines,
  });

  final String filePath;
  final String? unifiedDiff;
  final int? addedLines;
  final int? removedLines;
}

class _UnifiedDiffLineStats {
  const _UnifiedDiffLineStats({
    required this.addedLines,
    required this.removedLines,
  });

  final int addedLines;
  final int removedLines;
}

_UnifiedDiffLineStats? _unifiedDiffLineStats(String? unifiedDiff) {
  if (unifiedDiff == null || unifiedDiff.isEmpty) {
    return null;
  }

  var addedLines = 0;
  var removedLines = 0;

  for (final line in const LineSplitter().convert(unifiedDiff)) {
    if (_countsAsAddedLine(line)) {
      addedLines += 1;
    } else if (_countsAsRemovedLine(line)) {
      removedLines += 1;
    }
  }

  return _UnifiedDiffLineStats(
    addedLines: addedLines,
    removedLines: removedLines,
  );
}

bool _countsAsAddedLine(String line) {
  return line.startsWith('+') && !line.startsWith('+++');
}

bool _countsAsRemovedLine(String line) {
  return line.startsWith('-') && !line.startsWith('---');
}
