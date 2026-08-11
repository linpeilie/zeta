import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Claude Code CLI 无模型目录端点时使用的静态兜底目录。
///
/// 明确版本便于固定复现性，短别名由 Claude Code CLI 解析到当前版本。
const AgentModelList claudeCodeStaticModelCatalog = AgentModelList(
  models: <AgentModelInfo>[
    AgentModelInfo(
      id: 'claude-opus-4-7',
      model: 'claude-opus-4-7',
      displayName: 'Opus 4.7',
      description: '适合复杂推理与高难度编程任务。',
    ),
    AgentModelInfo(
      id: 'claude-sonnet-4-6',
      model: 'claude-sonnet-4-6',
      displayName: 'Sonnet 4.6',
      description: '性能、速度与成本的平衡选择。',
    ),
    AgentModelInfo(
      id: 'claude-haiku-4-5-20251001',
      model: 'claude-haiku-4-5-20251001',
      displayName: 'Haiku 4.5',
      description: '适合低延迟、轻量任务。',
    ),
    AgentModelInfo(
      id: 'opus',
      model: 'opus',
      displayName: 'Opus（最新别名）',
      description: '由 Claude Code CLI 解析到当前 Opus 版本。',
    ),
    AgentModelInfo(
      id: 'sonnet',
      model: 'sonnet',
      displayName: 'Sonnet（最新别名）',
      description: '由 Claude Code CLI 解析到当前 Sonnet 版本。',
      isDefault: true,
    ),
    AgentModelInfo(
      id: 'haiku',
      model: 'haiku',
      displayName: 'Haiku（最新别名）',
      description: '由 Claude Code CLI 解析到当前 Haiku 版本。',
    ),
  ],
);

/// Claude Code 模型目录入口；T30 只提供无网络的静态目录。
final class ClaudeCodeModelCatalog {
  const ClaudeCodeModelCatalog();

  AgentModelList listModels({int limit = 20, bool includeHidden = false}) {
    // 目录仅 6 项且无隐藏项，始终整体返回，避免静态条目被伪分页丢失。
    return claudeCodeStaticModelCatalog;
  }
}
