import 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_model_catalog_port_adapter.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_composition.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 由 app 组合层预先绑好 data 依赖、只等 Shell 相关入参的工作台组合工厂。
///
/// `IdeHome` 需要在 `initState` 里拿到 Shell 之后才能建工作台组合，但它**不应该
/// 为此看到 Repository**。所以 app 层把 Repository / registry / 文本目录都闭包进
/// 这个工厂，`IdeHome` 只转交 Shell 持有的只读事实源。
typedef IdeWorkbenchCompositionFactory =
    IdeWorkbenchComposition Function({
      required AgentManagementRuntimeFactSource runtimeFactSource,
    });

/// 工作台级 feature 组合的唯一构造点。
///
/// `IdeHome` 只组合 Workbench slot 并消费 selector；**哪个 Provider 用哪个
/// management Repository** 这类装配决策收在这里。在此之前这三个 Repository 是
/// 在 `IdeHome.initState` 里直接 `new` 出来的，等于 `lib/src/ui` 直接 import 了
/// `features/*/data/`，把 UI 层钉死在具体 Provider 的 data 实现上（违反 G6）。
///
/// 生命周期：本组合创建的 owner 由 [dispose] 反序释放，`IdeHome` 不再单独关闭
/// 注入进来的 owner。
final class IdeWorkbenchComposition {
  IdeWorkbenchComposition._(this.agentManagementComposition);

  /// 按当前 Provider 目录组装 Agent Management 的 Repository 与 slice 组合。
  factory IdeWorkbenchComposition.create({
    required Iterable<AgentManagementContribution> contributions,
    required AgentModelCatalogRepository modelCatalogRepository,
    required AgentProviderRuntimeRegistry runtimeRegistry,
    required AgentProviderSettingsPort providerSettings,
    required AgentManagementRuntimeFactSource runtimeFactSource,
    required AgentManagementTextCatalog textCatalog,
  }) {
    final byId = <String, AgentManagementContribution>{};
    for (final contribution in contributions) {
      if (contribution.providerId != contribution.definition.id ||
          byId.containsKey(contribution.providerId)) {
        throw StateError('Duplicate or mismatched Agent management identity');
      }
      byId[contribution.providerId] = contribution;
    }
    if (byId.isEmpty) {
      throw StateError('No plugin contributed agent management repositories');
    }
    final services = AgentManagementHostServices(
      textCatalog: textCatalog,
      runtimeRegistry: runtimeRegistry,
      modelCatalog: AgentManagementModelCatalogPortAdapter(
        modelCatalogRepository,
      ),
    );
    final repositories = <String, AgentCliManagementRepository>{
      for (final c in byId.values) c.providerId: c.createRepository(services),
    };
    for (final entry in repositories.entries) {
      if (entry.key != entry.value.agentId) {
        throw StateError('Agent management repository identity mismatch');
      }
    }
    return IdeWorkbenchComposition._(
      AgentManagementSliceComposition.create(
        repositories: repositories,
        definitions: {for (final c in byId.values) c.providerId: c.definition},
        providerSettings: providerSettings,
        runtimeFactSource: runtimeFactSource,
        textCatalog: textCatalog,
      ),
    );
  }

  /// Agent Management 的唯一状态与副作用组合。
  final AgentManagementSliceComposition agentManagementComposition;

  /// 反序释放本组合创建的 owner。
  void dispose() {
    agentManagementComposition.close();
  }
}
