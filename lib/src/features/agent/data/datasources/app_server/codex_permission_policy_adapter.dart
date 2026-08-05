import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/mappers/codex_permission_policy_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.codex_permission_policy');

/// 发送 JSON-RPC 请求并返回原始结果（由 provider/client 注入）。
typedef CodexPermissionRpcSender =
    Future<Object?> Function(String method, {Map<String, Object?> params});

/// Codex 权限策略 adapter：实现中立 [AgentPermissionPolicyPort]。
///
/// 负责完整分页 `permissionProfile/list`、built-in label、自定义 profile、
/// 选择应用到 runtime 快照。协议编解码委托 [CodexPermissionPolicyCodec]。
final class CodexPermissionPolicyAdapter implements AgentPermissionPolicyPort {
  /// 创建 adapter。
  ///
  /// [ensureInitialized] 在 list 前保证 app-server 已握手。
  /// [onSelectionApplied] 将归一化快照写回 provider 内存。
  /// [currentSnapshot] 读取当前 runtime 快照（用于 merge 诊断）。
  CodexPermissionPolicyAdapter({
    required this.ensureInitialized,
    required this.sendRequest,
    required this.onSelectionApplied,
    required this.currentSnapshot,
  });

  final Future<void> Function() ensureInitialized;
  final CodexPermissionRpcSender sendRequest;
  final void Function(CodexPermissionRuntimeSnapshot snapshot)
  onSelectionApplied;
  final CodexPermissionRuntimeSnapshot Function() currentSnapshot;

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() async {
    await ensureInitialized();
    try {
      final options = await _listAllPermissionOptions();
      if (options.isEmpty) {
        _log.fine('permissionProfile/list empty; falling back to built-ins');
        return CodexPermissionPolicyCodec.staticBuiltInCatalog();
      }
      return CodexPermissionPolicyCodec.catalogFromOptions(options);
    } on Object catch (error, stackTrace) {
      _log.fine(
        'permissionProfile/list failed; falling back to built-ins',
        error,
        stackTrace,
      );
      // unsupported / 临时失败：静态内置，避免 UI 空目录。
      return CodexPermissionPolicyCodec.staticBuiltInCatalog();
    }
  }

  @override
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    final normalizedId = selection.optionId.trim();
    if (normalizedId.isEmpty) {
      final current = currentSnapshot();
      final fallbackId =
          current.selectedOptionId ??
          CodexPermissionPolicyCodec.defaultBuiltInOptionId;
      return AgentPermissionApplyResult(
        normalizedSelection: AgentPermissionSelection(optionId: fallbackId),
        scope: AgentPermissionApplyScope.runtime,
        warning: 'Empty permission option; kept previous selection',
      );
    }

    // 自定义 id 不要求 `:`；显式 profile 绑定，不得被 approval/sandbox 覆盖。
    final snapshot = CodexPermissionPolicyCodec.applySelection(
      AgentPermissionSelection(optionId: normalizedId),
    );
    onSelectionApplied(snapshot);
    final effectiveId =
        snapshot.selectedOptionId ??
        snapshot.permissionProfileId ??
        normalizedId;
    return AgentPermissionApplyResult(
      normalizedSelection: AgentPermissionSelection(optionId: effectiveId),
      // Codex 权限随 thread/turn 参数发送；内存选择立即更新，跨 thread 不自动广播。
      scope: AgentPermissionApplyScope.currentSession,
    );
  }

  /// 完整 cursor 分页读取 `permissionProfile/list`。
  Future<List<AgentPermissionOption>> _listAllPermissionOptions() async {
    final options = <AgentPermissionOption>[];
    final seenIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;
    do {
      final result = await sendRequest(
        'permissionProfile/list',
        params: <String, Object?>{
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        },
      );
      final map = _asStringKeyedMap(result) ?? const <String, Object?>{};
      final data = map['data'];
      if (data is List) {
        for (final item in data) {
          final entry = _asStringKeyedMap(item);
          if (entry == null) {
            continue;
          }
          final option = CodexPermissionPolicyCodec.optionFromRpcEntry(entry);
          if (option == null || !seenIds.add(option.id)) {
            continue;
          }
          options.add(option);
        }
      }
      final nextCursor = map['nextCursor'];
      if (nextCursor is String &&
          nextCursor.isNotEmpty &&
          seenCursors.add(nextCursor)) {
        cursor = nextCursor;
      } else {
        cursor = null;
      }
    } while (cursor != null);
    return options;
  }

  static Map<String, Object?>? _asStringKeyedMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}
