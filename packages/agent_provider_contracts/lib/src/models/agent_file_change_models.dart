/// 文件变更的中立动作。
///
/// 只能由 Provider 的结构化语义决定；共享层和 UI 不得根据路径、正文或空字符串猜测。
enum AgentFileChangeKind { created, modified, deleted, moved, unknown }

/// 文件变更证据能否通过 Provider 的历史或 replay 路径重建。
enum AgentFileChangeReplayability {
  /// live、history 与 replay 都可恢复的证据。
  replayable,

  /// 只在当前实时回合存在的降级证据。
  liveOnly,
}

/// Provider 给出的中立文件内容证据。
///
/// `null` evidence 表示只有路径与动作摘要；它不是额外的证据变体。
sealed class AgentFileChangeEvidence {
  const AgentFileChangeEvidence();
}

/// Provider 给出的替换前后片段。
///
/// [oldText] 与 [newText] 都只是替换片段，不代表完整文件快照；空字符串是合法值。
final class AgentTextReplacementEvidence extends AgentFileChangeEvidence {
  const AgentTextReplacementEvidence({
    required this.oldText,
    required this.newText,
    this.replaceAll,
  });

  /// Provider 给出的替换前片段。
  final String oldText;

  /// Provider 给出的替换后片段。
  final String newText;

  /// Provider 是否明确要求替换全部匹配项；`null` 表示未提供该事实。
  final bool? replaceAll;
}

/// Provider 给出的写入内容。
///
/// 是否已经写入成功由所属工具的状态决定；空字符串是合法的写入内容。
final class AgentWrittenContentEvidence extends AgentFileChangeEvidence {
  const AgentWrittenContentEvidence({required this.content});

  /// Provider 给出的写入内容。
  final String content;
}

/// Provider 给出的 unified patch。
///
/// patch 原样保留为展示证据，不用于反推文件身份、动作或完整文件快照。
final class AgentUnifiedPatchEvidence extends AgentFileChangeEvidence {
  const AgentUnifiedPatchEvidence({required this.patch});

  /// Provider 给出的 unified patch；空字符串仍是合法的显式值。
  final String patch;
}

/// 单个有稳定身份的文件变更。
final class AgentFileChange {
  const AgentFileChange({
    required this.id,
    required this.path,
    required this.kind,
    this.destinationPath,
    this.evidence,
  });

  /// owner scope 内稳定的 change id，由 Provider adapter 决定。
  final String id;

  /// Provider 明确给出的源路径或目标文件路径。
  final String path;

  /// move 的目标路径；Provider 未提供时为 `null`。
  final String? destinationPath;

  /// Provider 明确映射出的动作。
  final AgentFileChangeKind kind;

  /// 可选内容证据；`null` 表示只有结构化摘要。
  final AgentFileChangeEvidence? evidence;
}

/// 一个 owner 在某次更新时的完整、累计文件变更快照。
///
/// Provider adapter 必须在进入共享 pipeline 前完成 identity、顺序与累计语义。
/// [changes] 会在构造时防御性复制；空列表是权威清空，不等同于“没有 snapshot”。
final class AgentFileChangeSnapshot {
  AgentFileChangeSnapshot({
    required this.revision,
    required this.replayability,
    required List<AgentFileChange> changes,
  }) : changes = List<AgentFileChange>.unmodifiable(changes);

  /// owner 内单调递增的内容版本，由 Provider-local tracker 维护。
  final int revision;

  /// 该证据能否从 Provider history/replay 恢复。
  final AgentFileChangeReplayability replayability;

  /// 有序、不可变的完整变更列表。
  final List<AgentFileChange> changes;
}
