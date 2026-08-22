import 'dart:async';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/mappers/codex_permission_policy_codec.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

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
  CodexPermissionPolicyAdapter({
    required this.ensureInitialized,
    required this.sendRequest,
  });

  final Future<void> Function() ensureInitialized;
  final CodexPermissionRpcSender sendRequest;

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() async {
    await ensureInitialized();
    try {
      final options = await _listAllPermissionOptions();
      return CodexPermissionPolicyCodec.catalogFromOptions(options);
    } on Object catch (error, stackTrace) {
      final kind = _classifyPermissionCatalogFailure(error);
      if (kind == _CodexPermissionCatalogFailureKind.unsupportedRuntime) {
        _log.t(
          'permissionProfile/list unsupported; falling back to built-ins',
          error: error,
          stackTrace: stackTrace,
        );
        return CodexPermissionPolicyCodec.staticBuiltInCatalog();
      }
      _log.t(
        'permissionProfile/list failed '
        '(${kind.name}); preserving caller catalog by rethrowing',
        error: error,
        stackTrace: stackTrace,
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
      throw ArgumentError.value(
        selection.optionId,
        'selection.optionId',
        'permission option id cannot be empty',
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
      if (data is! List) {
        throw const FormatException(
          'permissionProfile/list data is not a list',
        );
      }
      for (final item in data) {
        final entry = _asStringKeyedMap(item);
        if (entry == null ||
            (entry['allowed'] != null && entry['allowed'] is! bool) ||
            (entry['description'] != null && entry['description'] is! String)) {
          throw const FormatException(
            'permissionProfile/list contains a malformed option',
          );
        }
        final option = CodexPermissionPolicyCodec.optionFromRpcEntry(entry);
        if (option == null) {
          throw const FormatException(
            'permissionProfile/list contains an option without a valid id',
          );
        }
        if (seenIds.add(option.id)) {
          options.add(option);
        }
      }
      final nextCursor = map['nextCursor'];
      if (nextCursor != null && nextCursor is! String) {
        throw const FormatException(
          'permissionProfile/list nextCursor is not a string',
        );
      }
      final normalizedCursor = (nextCursor as String?)?.trim();
      if (normalizedCursor == null ||
          normalizedCursor.isEmpty ||
          !seenCursors.add(normalizedCursor)) {
        cursor = null;
      } else {
        cursor = normalizedCursor;
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
          message.contains('method not found')) {
        return _CodexPermissionCatalogFailureKind.unsupportedRuntime;
      }
      // 其它 JSON-RPC 业务错误视为临时/可重试，避免用 built-ins 覆盖。
      return _CodexPermissionCatalogFailureKind.transientFailure;
    }
    // 未结构化异常不得依赖文本猜测 unsupported；一律视为可重试失败。
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
