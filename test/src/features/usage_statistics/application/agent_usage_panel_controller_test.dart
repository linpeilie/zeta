import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

void main() {
  test('目录到达即发布状态，Provider 可乱序完成且保持目录顺序', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final refresh = controller.refresh(forceRefresh: false);
    final events = repository.controllers.single;
    events.add(_directory);
    await _flushEvents();

    expect(controller.providers.map(_providerId), <String>['codex', 'grok']);
    expect(
      controller.providers,
      everyElement(isA<AgentUsagePanelProviderState>()),
    );
    expect(controller.providers, everyElement(_isLoading));
    expect(controller.selectedProviderId, 'codex');
    expect(repository.forceRefreshValues, <bool>[false]);

    controller.selectProvider('grok');
    events.add(
      const AgentUsagePanelProviderLoaded(
        AgentUsagePanelEntry(providerId: 'grok', providerName: 'Grok'),
      ),
    );
    await _flushEvents();

    expect(controller.providers.map(_providerId), <String>['codex', 'grok']);
    expect(controller.providers.first.isLoading, isTrue);
    expect(controller.providers.last.isLoading, isFalse);
    expect(controller.selectedProviderId, 'grok');

    events
      ..add(
        const AgentUsagePanelProviderLoaded(
          AgentUsagePanelEntry(providerId: 'codex', providerName: 'Codex'),
        ),
      )
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21)))
      ..close();
    await refresh;

    expect(controller.isLoading, isFalse);
    expect(controller.lastUpdated, DateTime(2026, 7, 21));
  });

  test('刷新按 ID 保留旧数据，并将失败限制在对应 Provider', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final initialRefresh = controller.refresh();
    final initialEvents = repository.controllers.single;
    initialEvents
      ..add(_directory)
      ..add(
        const AgentUsagePanelProviderLoaded(
          AgentUsagePanelEntry(providerId: 'codex', providerName: 'Codex'),
        ),
      )
      ..add(
        const AgentUsagePanelProviderLoaded(
          AgentUsagePanelEntry(providerId: 'grok', providerName: 'Grok'),
        ),
      )
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21)))
      ..close();
    await initialRefresh;
    controller.selectProvider('grok');

    final refresh = controller.refresh();
    final refreshEvents = repository.controllers.last;
    expect(controller.providers, everyElement(_hasStaleLoadingData));

    refreshEvents.add(
      AgentUsagePanelProvidersDiscovered(
        providers: const <AgentUsagePanelProvider>[
          AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
          AgentUsagePanelProvider(providerId: 'codex', providerName: 'Codex'),
        ],
      ),
    );
    await _flushEvents();
    expect(controller.providers.map(_providerId), <String>['grok', 'codex']);
    expect(controller.selectedProviderId, 'grok');
    expect(controller.selectedProvider?.entry, isNotNull);

    refreshEvents
      ..add(
        const AgentUsagePanelProviderFailed(
          provider: AgentUsagePanelProvider(
            providerId: 'grok',
            providerName: 'Grok',
          ),
          message: 'Grok 暂时不可用',
        ),
      )
      ..add(
        const AgentUsagePanelProviderLoaded(
          AgentUsagePanelEntry(providerId: 'codex', providerName: 'Codex'),
        ),
      )
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 22)))
      ..close();
    await refresh;

    expect(controller.selectedProvider?.entry, isNotNull);
    expect(controller.selectedProvider?.loadError, 'Grok 暂时不可用');
    expect(controller.errorMessage, isNull);
  });

  test('静默刷新保留旧数据且不进入 isLoading', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final initialRefresh = controller.refresh();
    final initialEvents = repository.controllers.single;
    initialEvents
      ..add(_directory)
      ..add(
        const AgentUsagePanelProviderLoaded(
          AgentUsagePanelEntry(providerId: 'codex', providerName: 'Codex'),
        ),
      )
      ..add(
        const AgentUsagePanelProviderLoaded(
          AgentUsagePanelEntry(providerId: 'grok', providerName: 'Grok'),
        ),
      )
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21)))
      ..close();
    await initialRefresh;
    expect(controller.isLoading, isFalse);

    final silentRefresh = controller.refresh(showLoading: false);
    expect(controller.isLoading, isFalse);
    expect(controller.providers.every((state) => !state.isLoading), isTrue);
    expect(controller.providers.every((state) => state.entry != null), isTrue);

    final silentEvents = repository.controllers.last;
    silentEvents
      ..add(_directory)
      ..add(
        const AgentUsagePanelProviderLoaded(
          AgentUsagePanelEntry(
            providerId: 'codex',
            providerName: 'Codex Updated',
          ),
        ),
      )
      ..add(
        const AgentUsagePanelProviderLoaded(
          AgentUsagePanelEntry(providerId: 'grok', providerName: 'Grok'),
        ),
      )
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 22)))
      ..close();
    await silentRefresh;

    expect(controller.isLoading, isFalse);
    expect(controller.providers.first.entry?.providerName, 'Codex Updated');
    expect(controller.lastUpdated, DateTime(2026, 7, 22));
  });

  test('新刷新覆盖旧流，过期事件不会回写状态', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final staleRefresh = controller.refresh();
    final staleEvents = repository.controllers.single;
    staleEvents.add(_directory);
    await _flushEvents();

    final currentRefresh = controller.refresh();
    final currentEvents = repository.controllers.last;
    currentEvents.add(
      AgentUsagePanelProvidersDiscovered(
        providers: const <AgentUsagePanelProvider>[
          AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
        ],
      ),
    );
    await _flushEvents();

    staleEvents.add(
      const AgentUsagePanelProviderLoaded(
        AgentUsagePanelEntry(providerId: 'codex', providerName: '旧 Codex'),
      ),
    );
    await _flushEvents();
    expect(controller.providers.map(_providerId), <String>['grok']);

    currentEvents
      ..add(
        const AgentUsagePanelProviderLoaded(
          AgentUsagePanelEntry(providerId: 'grok', providerName: 'Grok'),
        ),
      )
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 22)))
      ..close();
    await currentRefresh;
    await staleEvents.close();
    await staleRefresh;

    expect(controller.providers.single.provider.providerId, 'grok');
    expect(controller.providers.single.entry?.providerName, 'Grok');
  });

  test('有效恢复值选中对应 Provider 且不触发回写', () async {
    final repository = _ControlledPanelRepository();
    final selectionChanges = <String?>[];
    final controller = AgentUsagePanelController(
      repository: repository,
      initialPreferredProviderId: ' grok ',
      onSelectionChanged: selectionChanges.add,
    );
    addTearDown(controller.dispose);

    final refresh = controller.refresh();
    repository.controllers.single
      ..add(_directory)
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21)))
      ..close();
    await refresh;

    expect(controller.preferredProviderId, 'grok');
    expect(controller.selectedProviderId, 'grok');
    expect(selectionChanges, isEmpty);
  });

  test('失效恢复值按目录首项回退并回写一次', () async {
    final repository = _ControlledPanelRepository();
    final selectionChanges = <String?>[];
    final controller = AgentUsagePanelController(
      repository: repository,
      initialPreferredProviderId: 'missing',
      onSelectionChanged: selectionChanges.add,
    );
    addTearDown(controller.dispose);

    final refresh = controller.refresh();
    repository.controllers.single
      ..add(_directory)
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21)))
      ..close();
    await refresh;

    expect(controller.preferredProviderId, 'codex');
    expect(controller.selectedProviderId, 'codex');
    expect(selectionChanges, <String?>['codex']);
  });

  test('目录到达前保留最后一个 Turn 终态偏好', () async {
    final repository = _ControlledPanelRepository();
    final selectionChanges = <String?>[];
    final controller = AgentUsagePanelController(
      repository: repository,
      onSelectionChanged: selectionChanges.add,
    );
    addTearDown(controller.dispose);

    controller
      ..selectProviderFromTurn('codex')
      ..selectProviderFromTurn('grok');

    expect(controller.preferredProviderId, 'grok');
    expect(controller.selectedProviderId, isNull);
    expect(selectionChanges, <String?>['codex', 'grok']);

    final refresh = controller.refresh();
    repository.controllers.single
      ..add(_directory)
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21)))
      ..close();
    await refresh;

    expect(controller.preferredProviderId, 'grok');
    expect(controller.selectedProviderId, 'grok');
    expect(selectionChanges, <String?>['codex', 'grok']);
  });

  test('Turn 终态自动选择覆盖手动选择', () async {
    final repository = _ControlledPanelRepository();
    final selectionChanges = <String?>[];
    final controller = AgentUsagePanelController(
      repository: repository,
      onSelectionChanged: selectionChanges.add,
    );
    addTearDown(controller.dispose);
    final refresh = controller.refresh();
    repository.controllers.single
      ..add(_directory)
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21)))
      ..close();
    await refresh;
    selectionChanges.clear();

    controller
      ..selectProvider('grok')
      ..selectProviderFromTurn('codex');

    expect(controller.preferredProviderId, 'codex');
    expect(controller.selectedProviderId, 'codex');
    expect(selectionChanges, <String?>['grok', 'codex']);
  });

  test('空目录清空恢复偏好和当前选择', () async {
    final repository = _ControlledPanelRepository();
    final selectionChanges = <String?>[];
    final controller = AgentUsagePanelController(
      repository: repository,
      initialPreferredProviderId: 'grok',
      onSelectionChanged: selectionChanges.add,
    );
    addTearDown(controller.dispose);

    final refresh = controller.refresh();
    repository.controllers.single
      ..add(AgentUsagePanelProvidersDiscovered(providers: const []))
      ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 21)))
      ..close();
    await refresh;

    expect(controller.providers, isEmpty);
    expect(controller.preferredProviderId, isNull);
    expect(controller.selectedProviderId, isNull);
    expect(selectionChanges, <String?>[null]);
  });

  test(
    'restore API applies without callback and stale refresh cannot replace it',
    () async {
      final repository = _ControlledPanelRepository();
      final selectionChanges = <String?>[];
      final controller = AgentUsagePanelController(
        repository: repository,
        onSelectionChanged: selectionChanges.add,
      );
      addTearDown(controller.dispose);

      controller.restorePreferredProviderId('grok');
      final staleRefresh = controller.refresh();
      final staleEvents = repository.controllers.single;
      staleEvents.add(_directory);
      await _flushEvents();

      final currentRefresh = controller.refresh();
      final currentEvents = repository.controllers.last;
      currentEvents
        ..add(_directory)
        ..add(AgentUsagePanelLoadCompleted(DateTime(2026, 7, 22)))
        ..close();
      await currentRefresh;

      staleEvents
        ..add(
          AgentUsagePanelProvidersDiscovered(
            providers: const <AgentUsagePanelProvider>[
              AgentUsagePanelProvider(
                providerId: 'codex',
                providerName: 'Codex',
              ),
            ],
          ),
        )
        ..close();
      await staleRefresh;

      expect(controller.providers.map(_providerId), <String>['codex', 'grok']);
      expect(controller.preferredProviderId, 'grok');
      expect(controller.selectedProviderId, 'grok');
      expect(selectionChanges, isEmpty);
    },
  );
}

final _directory = AgentUsagePanelProvidersDiscovered(
  providers: <AgentUsagePanelProvider>[
    AgentUsagePanelProvider(providerId: 'codex', providerName: 'Codex'),
    AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
  ],
);

String _providerId(AgentUsagePanelProviderState state) =>
    state.provider.providerId;

bool _isLoading(AgentUsagePanelProviderState state) => state.isLoading;

bool _hasStaleLoadingData(AgentUsagePanelProviderState state) =>
    state.isLoading && state.entry != null;

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

class _ControlledPanelRepository implements AgentUsagePanelRepository {
  final List<StreamController<AgentUsagePanelLoadEvent>> controllers =
      <StreamController<AgentUsagePanelLoadEvent>>[];
  final List<bool> forceRefreshValues = <bool>[];

  @override
  Stream<AgentUsagePanelLoadEvent> load({bool forceRefresh = false}) {
    forceRefreshValues.add(forceRefresh);
    final controller = StreamController<AgentUsagePanelLoadEvent>();
    controllers.add(controller);
    return controller.stream;
  }
}
