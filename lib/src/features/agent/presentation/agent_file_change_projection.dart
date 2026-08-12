import 'dart:convert';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 文件变更详情的中立 presentation 投影。
sealed class AgentFileChangeDetailProjection {
  const AgentFileChangeDetailProjection();
}

/// 替换片段的前后行投影。
final class AgentTextReplacementDetailProjection
    extends AgentFileChangeDetailProjection {
  AgentTextReplacementDetailProjection({
    required List<String> beforeLines,
    required List<String> afterLines,
    required this.replaceAll,
  }) : beforeLines = List<String>.unmodifiable(beforeLines),
       afterLines = List<String>.unmodifiable(afterLines);

  final List<String> beforeLines;
  final List<String> afterLines;
  final bool? replaceAll;
}

/// 单侧写入内容的行投影。
final class AgentWrittenContentDetailProjection
    extends AgentFileChangeDetailProjection {
  AgentWrittenContentDetailProjection({required List<String> lines})
    : lines = List<String>.unmodifiable(lines);

  final List<String> lines;
}

/// unified patch 单行的展示语义。
enum AgentUnifiedPatchLineKind { metadata, hunkHeader, context, added, removed }

/// unified patch 中一行及其高亮类别。
final class AgentUnifiedPatchLineProjection {
  const AgentUnifiedPatchLineProjection({
    required this.text,
    required this.kind,
  });

  final String text;
  final AgentUnifiedPatchLineKind kind;
}

/// unified patch 的有序行投影。
final class AgentUnifiedPatchDetailProjection
    extends AgentFileChangeDetailProjection {
  AgentUnifiedPatchDetailProjection({
    required List<AgentUnifiedPatchLineProjection> lines,
  }) : lines = List<AgentUnifiedPatchLineProjection>.unmodifiable(lines);

  final List<AgentUnifiedPatchLineProjection> lines;
}

/// 一项文件证据的行统计。
final class AgentFileChangeLineStatistics {
  const AgentFileChangeLineStatistics({
    required this.totalLines,
    this.addedLines,
    this.removedLines,
  });

  final int totalLines;
  final int? addedLines;
  final int? removedLines;
}

/// Widget 可直接消费的一行文件变更摘要与详情。
final class AgentFileChangeItemProjection {
  const AgentFileChangeItemProjection({
    required this.ownerEntryId,
    required this.snapshotRevision,
    required this.replayability,
    required this.changeId,
    required this.path,
    required this.destinationPath,
    required this.kind,
    required this.statistics,
    required this.detail,
  });

  final String ownerEntryId;
  final int snapshotRevision;
  final AgentFileChangeReplayability replayability;
  final String changeId;
  final String path;
  final String? destinationPath;
  final AgentFileChangeKind kind;
  final AgentFileChangeLineStatistics? statistics;
  final AgentFileChangeDetailProjection? detail;

  /// resize/revision 更新时保持不变的 Widget identity。
  ({String ownerEntryId, String changeId}) get stableIdentity =>
      (ownerEntryId: ownerEntryId, changeId: changeId);
}

/// 一个 owner 的完整、有序文件变更投影。
final class AgentFileChangeProjection {
  AgentFileChangeProjection({
    required this.ownerEntryId,
    required this.revision,
    required this.replayability,
    required List<AgentFileChangeItemProjection> items,
  }) : items = List<AgentFileChangeItemProjection>.unmodifiable(items);

  final String ownerEntryId;
  final int revision;
  final AgentFileChangeReplayability replayability;
  final List<AgentFileChangeItemProjection> items;

  bool get isLiveOnly => replayability == AgentFileChangeReplayability.liveOnly;
}

/// 把一项 typed change 投影为展示数据，不读取 Provider raw 或 patch header 身份。
AgentFileChangeItemProjection projectAgentFileChange({
  required String ownerEntryId,
  required int snapshotRevision,
  required AgentFileChangeReplayability replayability,
  required AgentFileChange change,
}) {
  final detail = switch (change.evidence) {
    null => null,
    AgentTextReplacementEvidence(
      :final oldText,
      :final newText,
      :final replaceAll,
    ) =>
      AgentTextReplacementDetailProjection(
        beforeLines: _splitLines(oldText),
        afterLines: _splitLines(newText),
        replaceAll: replaceAll,
      ),
    AgentWrittenContentEvidence(:final content) =>
      AgentWrittenContentDetailProjection(lines: _splitLines(content)),
    AgentUnifiedPatchEvidence(:final patch) =>
      AgentUnifiedPatchDetailProjection(lines: _projectPatchLines(patch)),
  };
  final statistics = switch (detail) {
    null => null,
    AgentTextReplacementDetailProjection(
      :final beforeLines,
      :final afterLines,
    ) =>
      AgentFileChangeLineStatistics(
        totalLines: beforeLines.length + afterLines.length,
        addedLines: afterLines.length,
        removedLines: beforeLines.length,
      ),
    AgentWrittenContentDetailProjection(:final lines) =>
      AgentFileChangeLineStatistics(totalLines: lines.length),
    AgentUnifiedPatchDetailProjection(:final lines) =>
      AgentFileChangeLineStatistics(
        totalLines: lines.length,
        addedLines: lines
            .where((line) => line.kind == AgentUnifiedPatchLineKind.added)
            .length,
        removedLines: lines
            .where((line) => line.kind == AgentUnifiedPatchLineKind.removed)
            .length,
      ),
  };

  return AgentFileChangeItemProjection(
    ownerEntryId: ownerEntryId,
    snapshotRevision: snapshotRevision,
    replayability: replayability,
    changeId: change.id,
    path: change.path,
    destinationPath: change.destinationPath,
    kind: change.kind,
    statistics: statistics,
    detail: detail,
  );
}

List<String> _splitLines(String content) =>
    List<String>.unmodifiable(const LineSplitter().convert(content));

List<AgentUnifiedPatchLineProjection> _projectPatchLines(String patch) {
  return <AgentUnifiedPatchLineProjection>[
    for (final line in const LineSplitter().convert(patch))
      AgentUnifiedPatchLineProjection(text: line, kind: _patchLineKind(line)),
  ];
}

AgentUnifiedPatchLineKind _patchLineKind(String line) {
  if (line.startsWith('@@')) {
    return AgentUnifiedPatchLineKind.hunkHeader;
  }
  if (line.startsWith('+++') || line.startsWith('---')) {
    return AgentUnifiedPatchLineKind.metadata;
  }
  if (line.startsWith('+')) {
    return AgentUnifiedPatchLineKind.added;
  }
  if (line.startsWith('-')) {
    return AgentUnifiedPatchLineKind.removed;
  }
  if (line.startsWith('diff --git ') ||
      line.startsWith('index ') ||
      line.startsWith(r'\ No newline') ||
      line.startsWith('*** ')) {
    return AgentUnifiedPatchLineKind.metadata;
  }
  return AgentUnifiedPatchLineKind.context;
}
