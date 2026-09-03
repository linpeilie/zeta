import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/src/application/agent_conversation_timeline_store.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

const Object _unset = Object();

/// 单个会话由事件归约产生的状态。
///
/// 纯数据：不 import Flutter，全 final 字段，实现 == / hashCode。
/// 可单测、可 diff（P4 的 region 派生依赖这一点）。
@immutable
final class AgentConversationSessionState {
  const AgentConversationSessionState({
    required this.status,
    required this.session,
    required this.restoredSessionId,
    required this.threadOpenPhase,
    required this.threadRuntimeStatus,
    required this.threadWaitingOnApproval,
    required this.threadWaitingOnUserInput,
    required this.currentThreadTitle,
    required this.currentThreadPreview,
    required this.modelRerouteNotice,
    required this.sessionConfigOptions,
    required this.autoReviewsByTurnId,
    required this.latestDeniedAutoReview,
    required this.requiresResumedSelectedThread,
  });

  const AgentConversationSessionState.initial({required String defaultTitle})
    : status = const AgentProviderStatus.idle(),
      session = null,
      restoredSessionId = null,
      threadOpenPhase = AgentThreadOpenPhase.idle,
      threadRuntimeStatus = null,
      threadWaitingOnApproval = false,
      threadWaitingOnUserInput = false,
      currentThreadTitle = defaultTitle,
      currentThreadPreview = '',
      modelRerouteNotice = null,
      sessionConfigOptions = const <AgentSessionConfigOption>[],
      autoReviewsByTurnId = const <String, AgentAutoApprovalReviewEvent>{},
      latestDeniedAutoReview = null,
      requiresResumedSelectedThread = false;

  final AgentProviderStatus status;
  final AgentSession? session;
  final String? restoredSessionId;
  final AgentThreadOpenPhase threadOpenPhase;
  final AgentThreadRuntimeStatus? threadRuntimeStatus;
  final bool threadWaitingOnApproval;
  final bool threadWaitingOnUserInput;
  final String currentThreadTitle;
  final String currentThreadPreview;
  final String? modelRerouteNotice;
  final List<AgentSessionConfigOption> sessionConfigOptions;
  final Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId;
  final AgentAutoApprovalReviewEvent? latestDeniedAutoReview;
  final bool requiresResumedSelectedThread;

  AgentConversationSessionState withRestoredSessionId(String? value) {
    return copyWith(restoredSessionId: value);
  }

  AgentConversationSessionState copyWith({
    AgentProviderStatus? status,
    Object? session = _unset,
    Object? restoredSessionId = _unset,
    AgentThreadOpenPhase? threadOpenPhase,
    Object? threadRuntimeStatus = _unset,
    bool? threadWaitingOnApproval,
    bool? threadWaitingOnUserInput,
    String? currentThreadTitle,
    String? currentThreadPreview,
    Object? modelRerouteNotice = _unset,
    List<AgentSessionConfigOption>? sessionConfigOptions,
    Map<String, AgentAutoApprovalReviewEvent>? autoReviewsByTurnId,
    Object? latestDeniedAutoReview = _unset,
    bool? requiresResumedSelectedThread,
  }) {
    return AgentConversationSessionState(
      status: status ?? this.status,
      session: identical(session, _unset)
          ? this.session
          : session as AgentSession?,
      restoredSessionId: identical(restoredSessionId, _unset)
          ? this.restoredSessionId
          : restoredSessionId as String?,
      threadOpenPhase: threadOpenPhase ?? this.threadOpenPhase,
      threadRuntimeStatus: identical(threadRuntimeStatus, _unset)
          ? this.threadRuntimeStatus
          : threadRuntimeStatus as AgentThreadRuntimeStatus?,
      threadWaitingOnApproval:
          threadWaitingOnApproval ?? this.threadWaitingOnApproval,
      threadWaitingOnUserInput:
          threadWaitingOnUserInput ?? this.threadWaitingOnUserInput,
      currentThreadTitle: currentThreadTitle ?? this.currentThreadTitle,
      currentThreadPreview: currentThreadPreview ?? this.currentThreadPreview,
      modelRerouteNotice: identical(modelRerouteNotice, _unset)
          ? this.modelRerouteNotice
          : modelRerouteNotice as String?,
      sessionConfigOptions: sessionConfigOptions == null
          ? this.sessionConfigOptions
          : List<AgentSessionConfigOption>.unmodifiable(sessionConfigOptions),
      autoReviewsByTurnId: autoReviewsByTurnId == null
          ? this.autoReviewsByTurnId
          : Map<String, AgentAutoApprovalReviewEvent>.unmodifiable(
              autoReviewsByTurnId,
            ),
      latestDeniedAutoReview: identical(latestDeniedAutoReview, _unset)
          ? this.latestDeniedAutoReview
          : latestDeniedAutoReview as AgentAutoApprovalReviewEvent?,
      requiresResumedSelectedThread:
          requiresResumedSelectedThread ?? this.requiresResumedSelectedThread,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentConversationSessionState &&
        status.state == other.status.state &&
        status.message == other.status.message &&
        status.details == other.status.details &&
        session?.id == other.session?.id &&
        session?.providerId == other.session?.providerId &&
        session?.title == other.session?.title &&
        restoredSessionId == other.restoredSessionId &&
        threadOpenPhase == other.threadOpenPhase &&
        threadRuntimeStatus == other.threadRuntimeStatus &&
        threadWaitingOnApproval == other.threadWaitingOnApproval &&
        threadWaitingOnUserInput == other.threadWaitingOnUserInput &&
        currentThreadTitle == other.currentThreadTitle &&
        currentThreadPreview == other.currentThreadPreview &&
        modelRerouteNotice == other.modelRerouteNotice &&
        zetaListEquals(sessionConfigOptions, other.sessionConfigOptions) &&
        zetaMapEquals(autoReviewsByTurnId, other.autoReviewsByTurnId) &&
        latestDeniedAutoReview == other.latestDeniedAutoReview &&
        requiresResumedSelectedThread == other.requiresResumedSelectedThread;
  }

  @override
  int get hashCode => Object.hash(
    status.state,
    status.message,
    status.details,
    session?.id,
    session?.providerId,
    session?.title,
    restoredSessionId,
    threadOpenPhase,
    threadRuntimeStatus,
    threadWaitingOnApproval,
    threadWaitingOnUserInput,
    currentThreadTitle,
    currentThreadPreview,
    modelRerouteNotice,
    Object.hashAll(sessionConfigOptions),
    _autoReviewsHash,
    latestDeniedAutoReview,
    requiresResumedSelectedThread,
  );

  /// `Map.entries` 每次迭代都新建 [MapEntry]，而 [MapEntry] 不覆写
  /// `==` / `hashCode`（恒等语义）。直接 `Object.hashAll(map.entries)` 会让
  /// **同一个对象**两次读 `hashCode` 得到不同值，违反 Object 契约。
  ///
  /// 逐对 [Object.hash] 后走无序聚合：与 [zetaMapEquals] 的「键集合相同且逐键
  /// 值相等、与插入顺序无关」保持一致。
  int get _autoReviewsHash => Object.hashAllUnordered(<int>[
    for (final entry in autoReviewsByTurnId.entries)
      Object.hash(entry.key, entry.value),
  ]);
}
