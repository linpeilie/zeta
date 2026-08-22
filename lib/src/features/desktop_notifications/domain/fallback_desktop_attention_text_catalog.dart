import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart';

/// 测试与未注入目录时的简体中文等价文案，与当前 zh ARB 逐字一致。
class FallbackDesktopAttentionTextCatalog
    implements DesktopAttentionTextCatalog {
  const FallbackDesktopAttentionTextCatalog();

  @override
  String titleFor(AgentAttentionKind kind) {
    return switch (kind) {
      AgentAttentionKind.turnCompleted => '任务已完成',
      AgentAttentionKind.turnFailed => '任务执行失败',
      AgentAttentionKind.turnInterrupted => '任务已中断',
      AgentAttentionKind.permissionRequired => '需要确认权限',
      AgentAttentionKind.questionRequired => '需要回答问题',
      AgentAttentionKind.planApprovalRequired => '需要确认计划',
      AgentAttentionKind.planExecutionRequired => '计划可以执行',
    };
  }

  @override
  String get currentProjectName => '当前项目';

  @override
  String sessionBody(String projectName) => '$projectName · Agent 会话';

  @override
  String get linuxAction => '打开 Zeta';
}
