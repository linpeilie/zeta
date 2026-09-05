import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_model_selection_controller.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/agent_skills_catalog_controller.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 单个 Conversation 的 Composer 状态唯一 owner。
///
/// 模型、模式与 Skill 目录仍按各自语义独立转移，但它们共享同一 Conversation
/// 生命周期。组合根必须显式创建本对象；ViewModel 不再隐式补建任一旧 controller。
final class AgentConversationComposerStateOwner {
  AgentConversationComposerStateOwner({
    required this.modelSelection,
    required this.mode,
    required this.skills,
  });

  factory AgentConversationComposerStateOwner.create({
    required AgentProviderSettingsPort providerController,
    AgentUiTextCatalog? textCatalog,
    DateTime Function()? clock,
  }) {
    final catalog = textCatalog ?? const FallbackAgentUiTextCatalog();
    return AgentConversationComposerStateOwner(
      modelSelection: AgentConversationModelSelectionController(
        persistSelection: providerController.persistModelSelection,
        textCatalog: catalog,
        clock: clock,
      ),
      mode: AgentConversationModeController(textCatalog: catalog),
      skills: AgentSkillsCatalogController(),
    );
  }

  final AgentConversationModelSelectionController modelSelection;
  final AgentConversationModeController mode;
  final AgentSkillsCatalogController skills;

  bool _disposed = false;

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    modelSelection.dispose();
    mode.dispose();
    skills.dispose();
  }
}
