import 'package:agent_provider_contracts/src/models/agent_model_codec.dart';
import 'package:agent_provider_contracts/src/models/immutable_collections.dart';

/// 创建新会话时采用的历史边界。
sealed class AgentForkBoundary {
  const AgentForkBoundary();
}

/// 从当前 thread 的最新位置创建分支。
final class AgentForkCurrentHead extends AgentForkBoundary {
  const AgentForkCurrentHead();
}

/// 新分支保留到指定 turn（包含该 turn）为止。
final class AgentForkThroughTurn extends AgentForkBoundary {
  const AgentForkThroughTurn(this.turnId);

  /// 新分支最后保留的 turn id。
  final String turnId;
}

const Object agentThreadSummaryUnset = Object();

/// Zeta 新建会话时的本地占位标题（身份哨兵，含历史中文与英语）。
///
/// 详情头栏在生成正式名之前使用目录文案；**不得**把它写进列表
/// [AgentThreadSummary.title]，否则会伪装成正式 generated_title，挡住后续
/// 首条消息临时标题与 provider 异步改名。
const String agentDefaultThreadTitle = '新建会话';

/// 英语界面下的本地占位标题；与 [agentDefaultThreadTitle] 一样只作身份哨兵。
const String agentDefaultThreadTitleEn = 'New conversation';

/// Provider 协议侧常见的英文占位标题，不得当正式名回写。
const String agentProviderPlaceholderThreadTitle = 'New thread';

/// 是否为空/默认占位标题（不可作为列表或详情的正式 title 回写）。
///
/// 对所有 Provider 通用：Codex / Grok 新建 thread 的 snapshot 与 session 都可能
/// 短暂携带「New thread」或空串；Zeta 本地占位为 [agentDefaultThreadTitle]
/// 或其英语等价。
bool isAgentThreadTitlePlaceholder(String? title) {
  final trimmed = title?.trim() ?? '';
  return trimmed.isEmpty ||
      trimmed == agentDefaultThreadTitle ||
      trimmed == agentDefaultThreadTitleEn ||
      trimmed == agentProviderPlaceholderThreadTitle;
}

/// Agent thread 当前运行状态。
///
/// 对应 Codex `ThreadStatus.type`；`active` 时还可携带
/// [AgentThreadSummary.waitingOnApproval] /
/// [AgentThreadSummary.waitingOnUserInput]。
enum AgentThreadRuntimeStatus { notLoaded, idle, active, systemError, unknown }

/// 项目列表中展示的 thread 摘要。
///
/// 该模型只保存列表展示和恢复会话所需的轻量信息；完整 turn/items 历史仍由
/// provider 在恢复或读取 thread 时按需获取。
final class AgentThreadSummary {
  AgentThreadSummary({
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
    this.waitingOnApproval = false,
    this.waitingOnUserInput = false,
    Map<String, Object?> raw = const <String, Object?>{},
  }) : raw = immutableJsonMap(raw);

  /// provider thread id。
  final String id;

  /// 创建或返回该 thread 的 provider id。
  final String providerId;

  /// thread 捕获的工作目录，通常等于项目根目录。
  final String projectPath;

  /// 用户可读标题；为空时 UI 会回退到 [preview] 或短 id。
  final String? title;

  /// Provider 恢复历史所需的可选 locator。
  ///
  /// Provider 可保存本地 session 文件、目录或工作区路径。
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

  /// 是否在等待用户审批（仅 `active` 时有意义）。
  final bool waitingOnApproval;

  /// 是否在等待用户输入（仅 `active` 时有意义）。
  final bool waitingOnUserInput;

  /// 原始 provider payload，便于调试和未来补齐字段。
  final Map<String, Object?> raw;

  /// 摘要字段是否带有忙碌/等待标记。
  ///
  /// 列表 UI 应以 Zeta 本进程 live 的 `runningThreadIds` 为准；从 provider
  /// `thread/list` 写入前会剥离未由 Zeta 持有的 active/waiting，避免把外部
  /// 客户端正在跑的会话显示成 Zeta 执行中。
  bool get isBusy =>
      status == AgentThreadRuntimeStatus.active ||
      waitingOnApproval ||
      waitingOnUserInput;

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
    bool? waitingOnApproval,
    bool? waitingOnUserInput,
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
      waitingOnApproval: waitingOnApproval ?? this.waitingOnApproval,
      waitingOnUserInput: waitingOnUserInput ?? this.waitingOnUserInput,
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
      'waitingOnApproval': waitingOnApproval,
      'waitingOnUserInput': waitingOnUserInput,
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
      waitingOnApproval: map['waitingOnApproval'] == true,
      waitingOnUserInput: map['waitingOnUserInput'] == true,
      raw: raw,
    );
  }
}

/// thread 分页查询参数。
final class AgentThreadListQuery {
  AgentThreadListQuery({
    required this.projectPath,
    required this.limit,
    this.cursor,
    this.archived = false,
    this.searchTerm,
    List<String> sourceKinds = const <String>[],
  }) : sourceKinds = immutableList(sourceKinds);

  /// 用 provider cwd 精确匹配项目；为空时跨项目读取。
  final String? projectPath;

  /// 单页请求数量。
  final int limit;

  /// provider 返回的不透明分页游标。
  final String? cursor;

  /// 是否只返回已归档线程；`false` 为活动线程（默认）。
  final bool archived;

  /// 可选标题子串搜索（对应协议 `searchTerm`）。
  final String? searchTerm;

  /// provider 原生来源类型过滤；空列表表示使用 provider 默认范围。
  final List<String> sourceKinds;
}

/// thread 分页结果。
final class AgentThreadPage {
  AgentThreadPage({
    required List<AgentThreadSummary> threads,
    required this.nextCursor,
  }) : threads = immutableList(threads);

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
