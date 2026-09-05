import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Zeta 自有桌面提醒文案目录。
///
/// 只接收中立 [AgentAttentionKind] 与已截取的项目名，返回当前进程语言的字符串。
/// 不暴露 ARB key、Flutter `Locale`、`BuildContext` 或 Provider raw payload。
abstract interface class DesktopAttentionTextCatalog {
  /// 按注意力类型返回通知标题。
  String titleFor(AgentAttentionKind kind);

  /// 路径无法解析项目名时的占位。
  String get currentProjectName;

  /// 安全通知正文；[projectName] 为已截取的最后路径段或 [currentProjectName]。
  String sessionBody(String projectName);

  /// Linux 通知默认动作标签。
  String get linuxAction;
}
