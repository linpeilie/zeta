import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 本地执行请求冻结的权限来源与 runtime 门闩。
final class AgentPlanExecutionPermissionSeed {
  const AgentPlanExecutionPermissionSeed({
    required this.selection,
    required this.runtimeIdentity,
    required this.threadId,
  });

  final AgentPermissionSelection? selection;
  final AgentProviderRuntimeIdentity? runtimeIdentity;
  final String threadId;
}

/// 管理 Plan 完成后、执行开始前的本地交接状态。
///
/// Controller 不依赖 Widget、时间线 Store 或 Provider 协议。调用方负责从当前
/// live turn 提取最终计划，并在用户选择“执行”后发起新的 Default 回合。
final class AgentPlanExecutionHandoffController {
  AgentPlanExecutionHandoffController({
    this.textCatalog = const FallbackAgentUiTextCatalog(),
  });

  final AgentUiTextCatalog textCatalog;
  AgentPlanExecutionRequest? _pendingRequest;
  AgentPlanExecutionPermissionSeed? _pendingPermissionSeed;
  AgentPlanExecutionPermissionOrigin? _pendingPermissionOrigin;
  _AgentProviderApprovedPlanCandidate? _providerApprovedCandidate;

  /// 当前待用户处理的本地计划执行请求。
  AgentPlanExecutionRequest? get pendingRequest => _pendingRequest;

  /// 读取当前请求的权限种子；陈旧请求返回 null。
  AgentPlanExecutionPermissionSeed? permissionSeedFor(
    AgentPlanExecutionRequest request,
  ) {
    return _pendingRequest?.id == request.id ? _pendingPermissionSeed : null;
  }

  /// 按当前 catalog 与 runtime 重新校验一次性执行权限。
  ///
  /// Provider 没有权限端口时保留 provider fallback；有端口但目录没有可用默认项
  /// 时返回 executionPermission=null，由 UI 禁止执行并要求显式选择。
  AgentPlanExecutionRequest? reconcileExecutionPermission({
    required AgentPlanExecutionRequest request,
    required bool supportsPermissionSelection,
    required Iterable<AgentPermissionOption> options,
    required AgentPermissionSelection? catalogDefault,
    required AgentProviderRuntimeIdentity? currentRuntimeIdentity,
  }) {
    if (_pendingRequest?.id != request.id) {
      return null;
    }
    if (!supportsPermissionSelection) {
      return _replacePendingPermission(
        request,
        AgentPlanExecutionPermissionChoice(
          label: textCatalog.providerDefaultPermission,
          origin: AgentPlanExecutionPermissionOrigin.providerFallback,
        ),
        seed: null,
        origin: AgentPlanExecutionPermissionOrigin.providerFallback,
      );
    }

    final available = List<AgentPermissionOption>.unmodifiable(options);
    final seed = _pendingPermissionSeed;
    final seedOrigin = _pendingPermissionOrigin;
    final seedIsCurrent =
        seed != null &&
        seed.threadId == request.sessionId &&
        seed.runtimeIdentity == currentRuntimeIdentity &&
        (seed.runtimeIdentity != null ||
            seedOrigin == AgentPlanExecutionPermissionOrigin.userOverride);
    final seededOption = seedIsCurrent
        ? _executableOption(available, seed.selection)
        : null;
    if (seededOption != null) {
      final origin =
          seedOrigin ?? AgentPlanExecutionPermissionOrigin.beforePlan;
      return _replacePendingPermission(
        request,
        AgentPlanExecutionPermissionChoice(
          selection: AgentPermissionSelection(optionId: seededOption.id),
          label: seededOption.label,
          origin: origin,
        ),
        seed: seed,
        origin: origin,
      );
    }

    final defaultOption =
        _executableOption(available, catalogDefault) ??
        _firstExecutableOption(available);
    if (defaultOption == null) {
      return _replacePendingPermission(request, null, seed: null, origin: null);
    }
    final fallbackSelection = AgentPermissionSelection(
      optionId: defaultOption.id,
    );
    return _replacePendingPermission(
      request,
      AgentPlanExecutionPermissionChoice(
        selection: fallbackSelection,
        label: defaultOption.label,
        origin: AgentPlanExecutionPermissionOrigin.catalogDefault,
      ),
      seed: AgentPlanExecutionPermissionSeed(
        selection: fallbackSelection,
        runtimeIdentity: currentRuntimeIdentity,
        threadId: request.sessionId,
      ),
      origin: AgentPlanExecutionPermissionOrigin.catalogDefault,
    );
  }

  /// 为当前执行卡选择一次性权限，不调用 Provider apply，也不更新持久化偏好。
  AgentPlanExecutionRequest? selectExecutionPermission({
    required AgentPlanExecutionRequest request,
    required AgentPermissionOption option,
    required AgentProviderRuntimeIdentity? currentRuntimeIdentity,
  }) {
    if (_pendingRequest?.id != request.id ||
        !option.allowed ||
        option.planningOnly) {
      return null;
    }
    final selection = AgentPermissionSelection(optionId: option.id);
    return _replacePendingPermission(
      request,
      AgentPlanExecutionPermissionChoice(
        selection: selection,
        label: option.label,
        origin: AgentPlanExecutionPermissionOrigin.userOverride,
      ),
      seed: AgentPlanExecutionPermissionSeed(
        selection: selection,
        runtimeIdentity: currentRuntimeIdentity,
        threadId: request.sessionId,
      ),
      origin: AgentPlanExecutionPermissionOrigin.userOverride,
    );
  }

  /// 暂存已由 Provider 接受、但仍在等待成功终态的 Plan。
  ///
  /// 这里只保存中立计划与权限选择，不向任何审批端口回写，也不启动回合。
  bool stageProviderApprovedPlan({
    required AgentPlanApprovalRequest request,
    required AgentPermissionSelection? executionPermission,
    required AgentProviderRuntimeIdentity? permissionRuntimeIdentity,
  }) {
    final sessionId = request.sessionId?.trim();
    final turnId = request.turnId?.trim();
    final markdown = request.markdown.trim();
    if (sessionId == null ||
        sessionId.isEmpty ||
        turnId == null ||
        turnId.isEmpty ||
        markdown.isEmpty) {
      return false;
    }
    _providerApprovedCandidate = _AgentProviderApprovedPlanCandidate(
      requestId: request.id,
      sessionId: sessionId,
      turnId: turnId,
      title: request.title.trim(),
      markdown: markdown,
      executionPermission: executionPermission,
      permissionRuntimeIdentity: permissionRuntimeIdentity,
    );
    return true;
  }

  /// 仅丢弃同一个 Provider Plan 审批暂存，避免旧回调清除新请求。
  /// 是否已有匹配该回合的 Provider 审批暂存（尚未被 offer 消费）。
  bool hasStagedProviderPlan({
    required String sessionId,
    required String turnId,
  }) {
    final candidate = _providerApprovedCandidate;
    return candidate != null &&
        candidate.sessionId == sessionId &&
        candidate.turnId == turnId;
  }

  bool discardStagedProviderPlan(String requestId) {
    if (_providerApprovedCandidate?.requestId != requestId) {
      return false;
    }
    _providerApprovedCandidate = null;
    return true;
  }

  /// 尝试为一个已完成的 Plan 回合创建执行交接请求。
  ///
  /// 非 Plan、非成功终态或没有可展示计划内容时返回 null，并清除旧请求。
  AgentPlanExecutionRequest? offerCompletedPlan({
    required String sessionId,
    required String turnId,
    required AgentHistoryTurnStatus status,
    required AgentConversationModeId? modeId,
    required String? planMarkdown,
    String? planMessageId,
    Iterable<AgentPlanEntry> planEntries = const <AgentPlanEntry>[],
    AgentPermissionSelection? executionPermission,
    AgentProviderRuntimeIdentity? permissionRuntimeIdentity,
  }) {
    final providerCandidate = _providerApprovedCandidate;
    if (providerCandidate != null &&
        providerCandidate.sessionId == sessionId &&
        providerCandidate.turnId == turnId) {
      _providerApprovedCandidate = null;
      if (status != AgentHistoryTurnStatus.completed &&
          status != AgentHistoryTurnStatus.interrupted) {
        _pendingRequest = null;
        _pendingPermissionSeed = null;
        _pendingPermissionOrigin = null;
        return null;
      }
      return _setPendingRequest(
        sessionId: sessionId,
        turnId: turnId,
        title: providerCandidate.title,
        markdown: providerCandidate.markdown,
        messageId: null,
        executionPermission: providerCandidate.executionPermission,
        permissionRuntimeIdentity: providerCandidate.permissionRuntimeIdentity,
      );
    }

    final normalizedMarkdown = planMarkdown?.trim();
    final hasProviderMarkdown =
        normalizedMarkdown != null && normalizedMarkdown.isNotEmpty;
    final markdown = _resolvedPlanMarkdown(planMarkdown, planEntries);
    if (status != AgentHistoryTurnStatus.completed ||
        modeId?.kind != AgentConversationModeKind.plan ||
        markdown == null) {
      _pendingRequest = null;
      _pendingPermissionSeed = null;
      _pendingPermissionOrigin = null;
      return null;
    }

    return _setPendingRequest(
      sessionId: sessionId,
      turnId: turnId,
      title: textCatalog.planReadyTitle,
      markdown: markdown,
      messageId: hasProviderMarkdown ? planMessageId : null,
      executionPermission: executionPermission,
      permissionRuntimeIdentity: permissionRuntimeIdentity,
    );
  }

  AgentPlanExecutionRequest _setPendingRequest({
    required String sessionId,
    required String turnId,
    required String title,
    required String markdown,
    required String? messageId,
    required AgentPermissionSelection? executionPermission,
    required AgentProviderRuntimeIdentity? permissionRuntimeIdentity,
  }) {
    final request = AgentPlanExecutionRequest(
      id: 'plan-execution:$sessionId:$turnId',
      sessionId: sessionId,
      turnId: turnId,
      title: title.isEmpty ? textCatalog.planReadyTitle : title,
      markdown: markdown,
      // 正文由结构化步骤合成时没有对应的 plan 消息，不能让 UI 误升级别的消息。
      messageId: messageId,
    );
    _pendingRequest = request;
    _pendingPermissionSeed = AgentPlanExecutionPermissionSeed(
      selection: executionPermission,
      runtimeIdentity: permissionRuntimeIdentity,
      threadId: sessionId,
    );
    _pendingPermissionOrigin = AgentPlanExecutionPermissionOrigin.beforePlan;
    return request;
  }

  AgentPlanExecutionRequest _replacePendingPermission(
    AgentPlanExecutionRequest request,
    AgentPlanExecutionPermissionChoice? choice, {
    required AgentPlanExecutionPermissionSeed? seed,
    required AgentPlanExecutionPermissionOrigin? origin,
  }) {
    final updated = request.copyWithExecutionPermission(choice);
    _pendingRequest = updated;
    _pendingPermissionSeed = seed;
    _pendingPermissionOrigin = origin;
    return updated;
  }

  /// 仅在 [request] 仍是当前请求时完成交接，避免旧卡片回调清除新状态。
  bool resolve(AgentPlanExecutionRequest request) {
    if (_pendingRequest?.id != request.id) {
      return false;
    }
    _pendingRequest = null;
    _pendingPermissionSeed = null;
    _pendingPermissionOrigin = null;
    return true;
  }

  /// 会话、Provider 或工作区切换时清除非持久化交接状态。
  bool clear() {
    if (_pendingRequest == null && _providerApprovedCandidate == null) {
      return false;
    }
    _pendingRequest = null;
    _pendingPermissionSeed = null;
    _pendingPermissionOrigin = null;
    _providerApprovedCandidate = null;
    return true;
  }

  String? _resolvedPlanMarkdown(
    String? planMarkdown,
    Iterable<AgentPlanEntry> planEntries,
  ) {
    final normalizedMarkdown = planMarkdown?.trim();
    if (normalizedMarkdown != null && normalizedMarkdown.isNotEmpty) {
      return normalizedMarkdown;
    }

    final steps = planEntries
        .map((entry) => entry.content.trim())
        .where((content) => content.isNotEmpty)
        .toList(growable: false);
    if (steps.isEmpty) {
      return null;
    }
    return <String>[
      '## Execution plan',
      '',
      for (var index = 0; index < steps.length; index += 1)
        '${index + 1}. ${steps[index]}',
    ].join('\n');
  }
}

AgentPermissionOption? _executableOption(
  Iterable<AgentPermissionOption> options,
  AgentPermissionSelection? selection,
) {
  if (selection == null) {
    return null;
  }
  for (final option in options) {
    if (option.id == selection.optionId &&
        option.allowed &&
        !option.planningOnly) {
      return option;
    }
  }
  return null;
}

AgentPermissionOption? _firstExecutableOption(
  Iterable<AgentPermissionOption> options,
) {
  for (final option in options) {
    if (option.allowed && !option.planningOnly) {
      return option;
    }
  }
  return null;
}

final class _AgentProviderApprovedPlanCandidate {
  const _AgentProviderApprovedPlanCandidate({
    required this.requestId,
    required this.sessionId,
    required this.turnId,
    required this.title,
    required this.markdown,
    required this.executionPermission,
    required this.permissionRuntimeIdentity,
  });

  final String requestId;
  final String sessionId;
  final String turnId;
  final String title;
  final String markdown;
  final AgentPermissionSelection? executionPermission;
  final AgentProviderRuntimeIdentity? permissionRuntimeIdentity;
}
