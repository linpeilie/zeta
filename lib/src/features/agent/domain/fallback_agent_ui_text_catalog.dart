import 'package:zeta/src/features/agent/domain/agent_ui_text_catalog.dart';

/// 测试与未注入目录时的简体中文等价文案，与当前 zh ARB 逐字一致。
final class FallbackAgentUiTextCatalog implements AgentUiTextCatalog {
  const FallbackAgentUiTextCatalog();

  @override
  String get thinkingToolTitle => '思考';
}
