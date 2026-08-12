import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Claude Code CLI `initialize` 返回的 Provider-local 白名单快照。
///
/// 快照只保留中立模型目录和套餐展示名，不携带账号身份、进程信息或原始协议载荷。
class ClaudeCodeCliMetadataSnapshot {
  const ClaudeCodeCliMetadataSnapshot({
    required this.models,
    this.subscriptionType,
  });

  /// 空快照用于损坏、不支持或没有可消费字段的响应。
  static const empty = ClaudeCodeCliMetadataSnapshot(
    models: AgentModelList(models: <AgentModelInfo>[]),
  );

  /// 当前 CLI 为本机账号返回的可选模型，顺序与 CLI 一致。
  final AgentModelList models;

  /// CLI 返回的套餐展示名；没有账号元数据时为空。
  final String? subscriptionType;
}
