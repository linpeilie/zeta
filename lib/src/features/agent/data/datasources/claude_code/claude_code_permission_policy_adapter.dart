import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_question_adapter.dart';
import 'package:zeta/src/features/agent/data/mappers/claude_code_permission_mode_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/fallback_agent_ui_text_catalog.dart';

final _log = loggerFor('zeta.agent.claude_code.permission_policy');

/// Claude Code 会话内对某类工具的固定决定。
enum ClaudeCodeSessionToolDecision { allow, deny }

/// 按 session 创建决策存储；组合层负责注入位于 `~/.zeta` 的具体文件。
typedef ClaudeCodeSessionDecisionStoreFactory =
    ClaudeCodeSessionDecisionStore Function(String sessionId);

/// 会话工具决策的持久化边界。
abstract interface class ClaudeCodeSessionDecisionStore {
  Future<Map<String, ClaudeCodeSessionToolDecision>> load();

  Future<void> save(Map<String, ClaudeCodeSessionToolDecision> decisions);
}

/// 不落盘的会话工具决策存储，供测试和无文件持久化的宿主使用。
final class MemoryClaudeCodeSessionDecisionStore
    implements ClaudeCodeSessionDecisionStore {
  Map<String, ClaudeCodeSessionToolDecision> _decisions =
      <String, ClaudeCodeSessionToolDecision>{};

  @override
  Future<Map<String, ClaudeCodeSessionToolDecision>> load() async {
    return Map<String, ClaudeCodeSessionToolDecision>.of(_decisions);
  }

  @override
  Future<void> save(
    Map<String, ClaudeCodeSessionToolDecision> decisions,
  ) async {
    _decisions = Map<String, ClaudeCodeSessionToolDecision>.of(decisions);
  }
}

/// 版本化、宽容解码的会话工具决策文件。
///
/// JSON 白名单只有 `version`、`toolName` 与 `decision`，绝不写入工具 input、
/// prompt、cwd 或 Provider raw payload。
final class FileClaudeCodeSessionDecisionStore
    implements ClaudeCodeSessionDecisionStore {
  FileClaudeCodeSessionDecisionStore({required File file})
    : _file = AtomicTextFile(file);

  static const int currentVersion = 1;

  final AtomicTextFile _file;

  @override
  Future<Map<String, ClaudeCodeSessionToolDecision>> load() async {
    try {
      final source = await _file.read();
      if (source == null || source.trim().isEmpty) {
        return <String, ClaudeCodeSessionToolDecision>{};
      }
      final decoded = jsonDecode(source);
      if (decoded is! Map || decoded['version'] != currentVersion) {
        return <String, ClaudeCodeSessionToolDecision>{};
      }
      final entries = decoded['decisions'];
      if (entries is! List) {
        return <String, ClaudeCodeSessionToolDecision>{};
      }
      final result = <String, ClaudeCodeSessionToolDecision>{};
      for (final item in entries) {
        if (item is! Map) {
          continue;
        }
        final toolName = item['toolName'];
        final rawDecision = item['decision'];
        if (toolName is! String || rawDecision is! String) {
          continue;
        }
        final normalizedToolName = toolName.trim();
        if (normalizedToolName.isEmpty) {
          continue;
        }
        final decision = switch (rawDecision) {
          'allow' => ClaudeCodeSessionToolDecision.allow,
          'deny' => ClaudeCodeSessionToolDecision.deny,
          _ => null,
        };
        if (decision != null) {
          result[normalizedToolName] = decision;
        }
      }
      return result;
    } catch (error) {
      // 会话缓存损坏或不可读不能阻断 Provider 启动；回退为空缓存。
      _log.w(
        'Could not load Claude Code session decisions '
        '(${error.runtimeType})',
      );
      return <String, ClaudeCodeSessionToolDecision>{};
    }
  }

  @override
  Future<void> save(
    Map<String, ClaudeCodeSessionToolDecision> decisions,
  ) async {
    final toolNames = decisions.keys.toList(growable: false)..sort();
    final payload = <String, Object?>{
      'version': currentVersion,
      'decisions': <Object?>[
        for (final toolName in toolNames)
          <String, Object?>{
            'toolName': toolName,
            'decision': decisions[toolName]!.name,
          },
      ],
    };
    await _file.write(jsonEncode(payload));
  }
}

/// 将新权限模式应用到 Claude Code 运行时，并返回真实生效范围。
typedef ClaudeCodePermissionModeApplier =
    Future<AgentPermissionApplyScope> Function(
      ClaudeCodePermissionMode permissionMode,
    );

/// Claude Code 权限策略 adapter。
///
/// `--permission-mode` 的进程重启由 Provider 回调执行；adapter 负责中立目录、
/// optionId 归一化，以及当前 session 的 always 决策缓存。
final class ClaudeCodePermissionPolicyAdapter
    implements AgentPermissionPolicyPort {
  ClaudeCodePermissionPolicyAdapter({
    required this.applyPermissionMode,
    ClaudeCodeSessionDecisionStoreFactory? sessionDecisionStoreFactory,
    this.textCatalog = const FallbackAgentUiTextCatalog(),
  }) : _sessionDecisionStoreFactory =
           sessionDecisionStoreFactory ??
           ((_) => MemoryClaudeCodeSessionDecisionStore());

  final ClaudeCodePermissionModeApplier applyPermissionMode;
  final ClaudeCodeSessionDecisionStoreFactory _sessionDecisionStoreFactory;
  final AgentUiTextCatalog textCatalog;

  ClaudeCodeSessionDecisionStore? _sessionDecisionStore;
  Map<String, ClaudeCodeSessionToolDecision> _sessionDecisions =
      <String, ClaudeCodeSessionToolDecision>{};

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() async {
    return ClaudeCodePermissionModeCodec.catalog(textCatalog: textCatalog);
  }

  @override
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    final mode = ClaudeCodePermissionModeCodec.parseOptionId(
      selection.optionId,
    );
    final scope = await applyPermissionMode(mode);
    return AgentPermissionApplyResult(
      normalizedSelection: AgentPermissionSelection(
        optionId: ClaudeCodePermissionModeCodec.optionId(mode),
      ),
      scope: scope,
    );
  }

  /// 绑定当前 session，并宽容加载该 session 的工具固定决定。
  Future<void> bindSession(String sessionId) async {
    final store = _sessionDecisionStoreFactory(sessionId);
    _sessionDecisionStore = store;
    final loaded = Map<String, ClaudeCodeSessionToolDecision>.of(
      await store.load(),
    );
    final removedInteractiveDecision = loaded.keys.any(
      _isInteractiveQuestionTool,
    );
    loaded.removeWhere((toolName, _) => _isInteractiveQuestionTool(toolName));
    _sessionDecisions = loaded;
    if (removedInteractiveDecision) {
      // 旧版本曾把 AskUserQuestion 错当权限并落盘。绑定时主动清理，避免恢复
      // 历史会话后继续静默 allow/deny；清理失败不能阻断会话启动。
      try {
        await store.save(
          Map<String, ClaudeCodeSessionToolDecision>.unmodifiable(
            _sessionDecisions,
          ),
        );
      } catch (error) {
        _log.w(
          'Could not remove stale Claude Code question decision '
          '(${error.runtimeType})',
        );
      }
    }
  }

  /// 查询当前 session 对 [toolName] 的固定决定。
  ClaudeCodeSessionToolDecision? decisionForTool(String toolName) {
    final normalized = toolName.trim();
    if (normalized.isEmpty || _isInteractiveQuestionTool(normalized)) {
      return null;
    }
    return _sessionDecisions[normalized];
  }

  /// 记住当前 session 对 [toolName] 的固定决定。
  ///
  /// 内存先提交，写盘失败由 Provider 记录但不撤销已经发给 CLI 的 live 决策。
  Future<void> rememberToolDecision(
    String toolName,
    ClaudeCodeSessionToolDecision decision,
  ) async {
    final normalized = toolName.trim();
    if (normalized.isEmpty || _isInteractiveQuestionTool(normalized)) {
      return;
    }
    _sessionDecisions[normalized] = decision;
    final store = _sessionDecisionStore;
    if (store != null) {
      await store.save(
        Map<String, ClaudeCodeSessionToolDecision>.unmodifiable(
          _sessionDecisions,
        ),
      );
    }
  }

  static bool _isInteractiveQuestionTool(String toolName) {
    return toolName.trim().toLowerCase() ==
        claudeCodeAskUserQuestionToolName.toLowerCase();
  }
}
