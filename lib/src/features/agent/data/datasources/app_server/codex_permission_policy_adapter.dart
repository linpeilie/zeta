import 'dart:async';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/mappers/codex_permission_policy_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

final _log = loggerFor('zeta.agent.codex_permission_policy');

/// 发送 JSON-RPC 请求并返回原始结果（由 provider/client 注入）。
typedef CodexPermissionRpcSender =
    Future<Object?> Function(String method, {Map<String, Object?> params});

/// `permissionProfile/list` 失败分类（adapter 内部；不泄漏到 domain）。
enum _CodexPermissionCatalogFailureKind {
  /// 运行时明确不支持该方法 → 可安全回退 built-ins。
  unsupportedRuntime,

  /// 超时、断线、server 错误等临时失败 → 向上抛出，保留旧目录。
  transientFailure,

  /// 响应形状损坏 → 向上抛出，不用空/静态目录覆盖。
  malformedResponse,
}

/// Codex 权限策略 adapter：实现中立 [AgentPermissionPolicyPort]。
///
/// 负责完整分页 `permissionProfile/list`、built-in label、自定义 profile、
/// 以及无副作用的 optionId 归一化。协议编码委托 [CodexPermissionPolicyCodec]。
final class CodexPermissionPolicyAdapter implements AgentPermissionPolicyPort {
  /// 创建 adapter。
  ///
  /// [ensureInitialized] 在 list 前保证 app-server 已握手。
  /// [fallbackOptionId] 仅处理异常空选择，不会被用户选择或 settings 回写修改。
  CodexPermissionPolicyAdapter({
    required this.ensureInitialized,
    required this.sendRequest,
    required this.fallbackOptionId,
  });

  final Future<void> Function() ensureInitialized;
  final CodexPermissionRpcSender sendRequest;
  final String fallbackOptionId;

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() async {
    await ensureInitialized();
    try {
      final options = await _listAllPermissionOptions();
      if (options.isEmpty) {
        // 空成功响应：固定契约为内置目录（与“无自定义 profile”语义一致）。
        _log.fine('permissionProfile/list empty; falling back to built-ins');
        return CodexPermissionPolicyCodec.staticBuiltInCatalog();
      }
      return CodexPermissionPolicyCodec.catalogFromOptions(options);
    } on Object catch (error, stackTrace) {
      final kind = _classifyPermissionCatalogFailure(error);
      if (kind == _CodexPermissionCatalogFailureKind.unsupportedRuntime) {
        _log.fine(
          'permissionProfile/list unsupported; falling back to built-ins',
          error,
          stackTrace,
        );
        return CodexPermissionPolicyCodec.staticBuiltInCatalog();
      }
      _log.fine(
        'permissionProfile/list failed '
        '(${kind.name}); preserving caller catalog by rethrowing',
        error,
        stackTrace,
      );
      // transient / malformed：向上抛出，由 controller 保留旧目录。
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    final normalizedId = selection.optionId.trim();
    if (normalizedId.isEmpty) {
      final configuredFallback = fallbackOptionId.trim();
      final fallbackId = configuredFallback.isEmpty
          ? CodexPermissionPolicyCodec.defaultBuiltInOptionId
          : configuredFallback;
      return AgentPermissionApplyResult(
        normalizedSelection: AgentPermissionSelection(optionId: fallbackId),
        scope: AgentPermissionApplyScope.currentSession,
        warning: 'Empty permission option; kept configured fallback',
      );
    }

    return AgentPermissionApplyResult(
      // 自定义 id 不要求 `:`；真正 profile/approval/sandbox 编码发生在每次请求。
      normalizedSelection: AgentPermissionSelection(optionId: normalizedId),
      scope: AgentPermissionApplyScope.currentSession,
    );
  }

  /// 完整 cursor 分页读取 `permissionProfile/list`。
  ///
  /// 任一页失败或损坏会抛出，调用方不得提交部分目录。
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
      final map = _asStringKeyedMap(result);
      if (map == null) {
        throw const FormatException(
          'permissionProfile/list result is not an object',
        );
      }
      final data = map['data'];
      if (data != null && data is! List) {
        throw const FormatException(
          'permissionProfile/list data is not a list',
        );
      }
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

  static _CodexPermissionCatalogFailureKind _classifyPermissionCatalogFailure(
    Object error,
  ) {
    if (error is FormatException) {
      return _CodexPermissionCatalogFailureKind.malformedResponse;
    }
    if (error is TimeoutException) {
      return _CodexPermissionCatalogFailureKind.transientFailure;
    }
    if (error is UnsupportedError) {
      return _CodexPermissionCatalogFailureKind.unsupportedRuntime;
    }
    if (error is JsonRpcException) {
      final message = error.error.message.toLowerCase();
      final experimentalDisabled =
          message.contains('experimental') &&
          (message.contains('disabled') || message.contains('not enabled'));
      if (error.error.code == -32601 ||
          experimentalDisabled ||
          message.contains('method not found') ||
          message.contains('not available') ||
          message.contains('not supported')) {
        return _CodexPermissionCatalogFailureKind.unsupportedRuntime;
      }
      // 其它 JSON-RPC 业务错误视为临时/可重试，避免用 built-ins 覆盖。
      return _CodexPermissionCatalogFailureKind.transientFailure;
    }
    final text = error.toString().toLowerCase();
    if (text.contains('method not found') || text.contains('-32601')) {
      return _CodexPermissionCatalogFailureKind.unsupportedRuntime;
    }
    return _CodexPermissionCatalogFailureKind.transientFailure;
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
