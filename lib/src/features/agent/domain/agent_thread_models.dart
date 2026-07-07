import 'package:zeta/src/features/agent/domain/agent_model_codec.dart';

const Object agentThreadSummaryUnset = Object();

/// Agent thread 当前运行状态。
enum AgentThreadRuntimeStatus { notLoaded, idle, active, systemError, unknown }

/// 项目列表中展示的 thread 摘要。
///
/// 该模型只保存列表展示和恢复会话所需的轻量信息；完整 turn/items 历史仍由
/// provider 在恢复或读取 thread 时按需获取。
class AgentThreadSummary {
  const AgentThreadSummary({
    required this.id,
    required this.providerId,
    required this.projectPath,
    required this.preview,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.title,
    this.sessionPath,
    this.recencyAt,
    this.raw = const <String, Object?>{},
  });

  /// provider thread id。
  final String id;

  /// 创建或返回该 thread 的 provider id。
  final String providerId;

  /// thread 捕获的工作目录，通常等于项目根目录。
  final String projectPath;

  /// 用户可读标题；为空时 UI 会回退到 [preview] 或短 id。
  final String? title;

  /// 本地 Codex session `jsonl` 路径。
  final String? sessionPath;

  /// 通常是首条用户消息。
  final String preview;

  /// 创建时间。
  final DateTime createdAt;

  /// 最近更新时间。
  final DateTime updatedAt;

  /// provider 用于排序的最近活动时间。
  final DateTime? recencyAt;

  /// 运行状态摘要。
  final AgentThreadRuntimeStatus status;

  /// 原始 provider payload，便于调试和未来补齐字段。
  final Map<String, Object?> raw;

  /// UI 展示名称。
  String get displayName {
    final cleanedTitle = title?.trim();
    if (cleanedTitle != null && cleanedTitle.isNotEmpty) {
      return cleanedTitle;
    }
    final cleanedPreview = preview.trim();
    if (cleanedPreview.isNotEmpty) {
      return cleanedPreview;
    }
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  /// 上次活跃时间，优先使用 provider 的 recency 排序时间。
  DateTime? get lastActiveAt => recencyAt ?? updatedAt;

  /// 旧展示标题入口，保留给尚未迁移的调用点。
  String get displayTitle => displayName;

  AgentThreadSummary copyWith({
    String? id,
    String? providerId,
    String? projectPath,
    Object? title = agentThreadSummaryUnset,
    Object? sessionPath = agentThreadSummaryUnset,
    String? preview,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? recencyAt = agentThreadSummaryUnset,
    AgentThreadRuntimeStatus? status,
    Map<String, Object?>? raw,
  }) {
    return AgentThreadSummary(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      projectPath: projectPath ?? this.projectPath,
      title: identical(title, agentThreadSummaryUnset)
          ? this.title
          : title as String?,
      sessionPath: identical(sessionPath, agentThreadSummaryUnset)
          ? this.sessionPath
          : sessionPath as String?,
      preview: preview ?? this.preview,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      recencyAt: identical(recencyAt, agentThreadSummaryUnset)
          ? this.recencyAt
          : recencyAt as DateTime?,
      status: status ?? this.status,
      raw: raw ?? this.raw,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'providerId': providerId,
      'projectPath': projectPath,
      'title': title,
      'sessionPath': sessionPath,
      'preview': preview,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'recencyAt': recencyAt?.millisecondsSinceEpoch,
      'status': status.name,
      'raw': raw,
    };
  }

  /// 从会话缓存宽容恢复 thread 摘要。
  static AgentThreadSummary? tryDecode(Object? value) {
    final map = decodeObjectMap(value);
    if (map.isEmpty) {
      return null;
    }

    final id = decodeOptionalString(map['id']);
    final providerId = decodeOptionalString(map['providerId']);
    final projectPath = decodeOptionalString(map['projectPath']);
    final createdAt = decodeDateTimeFromMilliseconds(map['createdAt']);
    final updatedAt = decodeDateTimeFromMilliseconds(map['updatedAt']);
    final raw = decodeObjectMap(map['raw']);
    if (id == null ||
        providerId == null ||
        projectPath == null ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }

    return AgentThreadSummary(
      id: id,
      providerId: providerId,
      projectPath: projectPath,
      title: decodeOptionalString(map['title']),
      sessionPath:
          decodeOptionalString(map['sessionPath']) ??
          decodeOptionalString(raw['path']),
      preview: decodeOptionalString(map['preview']) ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      recencyAt: decodeDateTimeFromMilliseconds(map['recencyAt']),
      status: _threadRuntimeStatus(map['status']),
      raw: raw,
    );
  }
}

/// thread 分页查询参数。
class AgentThreadListQuery {
  const AgentThreadListQuery({
    required this.projectPath,
    required this.limit,
    this.cursor,
  });

  /// 用 provider cwd 精确匹配项目。
  final String projectPath;

  /// 单页请求数量。
  final int limit;

  /// provider 返回的不透明分页游标。
  final String? cursor;
}

/// thread 分页结果。
class AgentThreadPage {
  const AgentThreadPage({required this.threads, required this.nextCursor});

  /// 当前页 thread 摘要。
  final List<AgentThreadSummary> threads;

  /// 下一页游标；为空表示没有更多。
  final String? nextCursor;
}

AgentThreadRuntimeStatus _threadRuntimeStatus(Object? value) {
  final statusName = decodeOptionalString(value);
  if (statusName == null) {
    return AgentThreadRuntimeStatus.unknown;
  }
  for (final status in AgentThreadRuntimeStatus.values) {
    if (status.name == statusName) {
      return status;
    }
  }
  return AgentThreadRuntimeStatus.unknown;
}
