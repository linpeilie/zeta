import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

void main() {
  test('刷新后选择首个 Provider，并在后续刷新中保留选择', () async {
    final repository = _PanelRepository(<AgentUsagePanelSnapshot>[
      _snapshot(const <AgentUsagePanelEntry>[
        AgentUsagePanelEntry(providerId: 'codex', providerName: 'Codex'),
        AgentUsagePanelEntry(providerId: 'grok', providerName: 'Grok'),
      ]),
      _snapshot(const <AgentUsagePanelEntry>[
        AgentUsagePanelEntry(providerId: 'grok', providerName: 'Grok'),
        AgentUsagePanelEntry(providerId: 'codex', providerName: 'Codex'),
      ]),
    ]);
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    await controller.refresh(forceRefresh: false);
    expect(controller.selectedProviderId, 'codex');
    expect(repository.forceRefreshValues, <bool>[false]);

    controller.selectProvider('grok');
    await controller.refresh();

    expect(controller.selectedProviderId, 'grok');
    expect(controller.selectedEntry?.providerName, 'Grok');
    expect(repository.forceRefreshValues, <bool>[false, true]);
  });

  test('刷新失败时保留旧条目并公开可重试错误', () async {
    final repository = _PanelRepository(<Object>[
      _snapshot(const <AgentUsagePanelEntry>[
        AgentUsagePanelEntry(providerId: 'codex', providerName: 'Codex'),
      ]),
      StateError('offline'),
    ]);
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    await controller.refresh();
    await controller.refresh();

    expect(controller.entries, hasLength(1));
    expect(controller.errorMessage, 'Agent 用量暂时无法读取');
    expect(controller.isLoading, isFalse);
  });
}

AgentUsagePanelSnapshot _snapshot(List<AgentUsagePanelEntry> entries) {
  return AgentUsagePanelSnapshot(
    entries: entries,
    refreshedAt: DateTime(2026, 7, 21),
  );
}

class _PanelRepository implements AgentUsagePanelRepository {
  _PanelRepository(this.results);

  final List<Object> results;
  final List<bool> forceRefreshValues = <bool>[];
  var _index = 0;

  @override
  Future<AgentUsagePanelSnapshot> load({bool forceRefresh = false}) async {
    forceRefreshValues.add(forceRefresh);
    final result = results[_index++];
    if (result is Error) {
      throw result;
    }
    return result as AgentUsagePanelSnapshot;
  }
}
