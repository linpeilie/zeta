import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_permission_mode_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.grok_permission_policy');

/// 发送 live 权限通知（由 provider 注入，best-effort）。
typedef GrokPermissionLiveNotifier =
    void Function(String method, Map<String, Object?> params);

/// Grok 权限策略 adapter：实现中立 [AgentPermissionPolicyPort]。
///
/// 协议映射委托 [GrokPermissionModeCodec]；本类协调 catalog、new/load meta、
/// live 通知、runtime 初始化状态与 apply scope。
final class GrokPermissionPolicyAdapter implements AgentPermissionPolicyPort {
  /// 创建 adapter。
  ///
  /// [isInitialized] / [isDisposed] 决定 live 通知是否发送。
  /// [onModeApplied] 写回 provider 内部 mode。
  /// [notifyLive] 发送单 method `_x.ai/yolo_mode_changed`。
  GrokPermissionPolicyAdapter({
    required this.isInitialized,
    required this.isDisposed,
    required this.currentMode,
    required this.onModeApplied,
    required this.notifyLive,
  });

  final bool Function() isInitialized;
  final bool Function() isDisposed;
  final GrokPermissionMode Function() currentMode;
  final void Function(GrokPermissionMode mode) onModeApplied;
  final GrokPermissionLiveNotifier notifyLive;

  /// 当前 mode 的 session/new|load `_meta`。
  Map<String, Object?> sessionMetaForCurrentMode() {
    return GrokPermissionModeCodec.sessionMeta(currentMode());
  }

  /// 指定 mode 的 session meta（测试与显式路径）。
  Map<String, Object?> sessionMetaForMode(GrokPermissionMode mode) {
    return GrokPermissionModeCodec.sessionMeta(mode);
  }

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() async {
    return GrokPermissionModeCodec.catalog();
  }

  @override
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    final next = GrokPermissionModeCodec.parse(selection.optionId);
    final wire = GrokPermissionModeCodec.wireId(next);
    final previous = currentMode();
    final changed = next != previous;
    onModeApplied(next);

    if (!changed) {
      return AgentPermissionApplyResult(
        normalizedSelection: AgentPermissionSelection(optionId: wire),
        scope: isInitialized() && !isDisposed()
            ? AgentPermissionApplyScope.runtime
            : AgentPermissionApplyScope.nextSession,
      );
    }

    if (!isInitialized() || isDisposed()) {
      // 未初始化：仅更新内存 mode；new/load 时通过 session meta 生效。
      return AgentPermissionApplyResult(
        normalizedSelection: AgentPermissionSelection(optionId: wire),
        scope: AgentPermissionApplyScope.nextSession,
        warning: isDisposed()
            ? 'Provider disposed; permission change was not broadcast'
            : null,
      );
    }

    final method = GrokPermissionModeCodec.yoloModeChangedMethod;
    final params = GrokPermissionModeCodec.yoloModeChangedParams(next);
    try {
      notifyLive(method, params);
    } catch (error, stackTrace) {
      _log.t(
        'Failed to notify $method for permission mode',
        error: error,
        stackTrace: stackTrace,
      );
      return AgentPermissionApplyResult(
        normalizedSelection: AgentPermissionSelection(optionId: wire),
        scope: AgentPermissionApplyScope.runtime,
        warning: 'Live permission notification failed; mode stored in memory',
      );
    }

    return AgentPermissionApplyResult(
      normalizedSelection: AgentPermissionSelection(optionId: wire),
      scope: AgentPermissionApplyScope.runtime,
    );
  }
}
