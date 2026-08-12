import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

void main() {
  test('首次只加载默认选中的 Provider', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final refresh = controller.refresh(forceRefresh: false);
    await _flushEvents();

    expect(controller.providers.map(_providerId), <String>['codex', 'grok']);
    expect(controller.selectedProviderId, 'codex');
    expect(repository.requests.map((request) => request.providerId), <String>[
      'codex',
    ]);
    expect(repository.requests.single.forceRefresh, isFalse);
    expect(controller.providers.first.isLoading, isTrue);
    expect(
      controller.providers.last.status,
      AgentUsagePanelProviderLoadStatus.notLoaded,
    );

    repository.requests.single.complete(_entry('codex', 'Codex'));
    await refresh;

    expect(controller.providers.first.entry?.providerName, 'Codex');
    expect(
      controller.providers.last.status,
      AgentUsagePanelProviderLoadStatus.notLoaded,
    );
  });

  test('切换到未加载 Tab 时按需加载，快速切换保留各自结果', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final initialRefresh = controller.refresh();
    await _flushEvents();
    final codexRequest = repository.requests.single;

    controller
      ..selectProvider('grok')
      ..selectProvider('codex')
      ..selectProvider('grok');
    await _flushEvents();

    expect(repository.requests.map((request) => request.providerId), <String>[
      'codex',
      'grok',
    ]);
    final grokRequest = repository.requests.last;
    grokRequest.complete(_entry('grok', 'Grok'));
    await _flushEvents();

    expect(controller.selectedProviderId, 'grok');
    expect(controller.selectedProvider?.entry?.providerName, 'Grok');
    expect(controller.providers.first.isLoading, isTrue);

    codexRequest.complete(_entry('codex', 'Codex'));
    await initialRefresh;

    expect(
      controller.providers.map((state) => state.entry?.providerId),
      <String?>['codex', 'grok'],
    );
  });

  test('已加载 Tab 再次选中不会重复查询', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final refresh = controller.refresh();
    await _flushEvents();
    repository.requests.single.complete(_entry('codex', 'Codex'));
    await refresh;

    controller.selectProvider('codex');
    await _flushEvents();

    expect(repository.requests, hasLength(1));
  });

  test('手动刷新只强制刷新当前 Provider，并保留旧数据', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final initialRefresh = controller.refresh();
    await _flushEvents();
    repository.requests.single.complete(_entry('codex', 'Codex'));
    await initialRefresh;

    controller.selectProvider('grok');
    await _flushEvents();
    repository.requests.last.complete(_entry('grok', 'Grok'));
    await _flushEvents();

    final refresh = controller.refresh();
    await _flushEvents();
    final request = repository.requests.last;

    expect(request.providerId, 'grok');
    expect(request.forceRefresh, isTrue);
    expect(controller.selectedProvider?.entry?.providerName, 'Grok');
    expect(controller.selectedProvider?.isLoading, isTrue);

    request.complete(_entry('grok', 'Grok Updated'));
    await refresh;

    expect(controller.selectedProvider?.entry?.providerName, 'Grok Updated');
    expect(controller.providers.first.entry?.providerName, 'Codex');
  });

  test('静默刷新保留旧数据且不进入当前 Tab 加载态', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final initialRefresh = controller.refresh();
    await _flushEvents();
    repository.requests.single.complete(_entry('codex', 'Codex'));
    await initialRefresh;

    final refresh = controller.refresh(showLoading: false);
    await _flushEvents();

    expect(controller.isLoading, isFalse);
    expect(controller.selectedProvider?.entry?.providerName, 'Codex');

    repository.requests.last.complete(_entry('codex', 'Codex Updated'));
    await refresh;
    expect(controller.selectedProvider?.entry?.providerName, 'Codex Updated');
  });

  test('目录同步只增加未加载 Tab，切换后才读取新增 Provider', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final initialRefresh = controller.refresh();
    await _flushEvents();
    repository.requests.single.complete(_entry('codex', 'Codex'));
    await initialRefresh;

    repository.directory = const <AgentUsagePanelProvider>[
      AgentUsagePanelProvider(providerId: 'codex', providerName: 'Codex'),
      AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
      AgentUsagePanelProvider(providerId: 'claude', providerName: 'Claude'),
    ];
    await controller.synchronizeProviders();

    expect(controller.providers.map(_providerId), <String>[
      'codex',
      'grok',
      'claude',
    ]);
    expect(repository.requests, hasLength(1));

    controller.selectProvider('claude');
    await _flushEvents();
    expect(repository.requests.last.providerId, 'claude');
    repository.requests.last.complete(_entry('claude', 'Claude'));
    await _flushEvents();
    expect(controller.selectedProvider?.entry?.providerName, 'Claude');
  });

  test('目录移除 Provider 后丢弃它的迟到结果', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final staleRefresh = controller.refresh();
    await _flushEvents();
    final staleCodex = repository.requests.single;

    repository.directory = const <AgentUsagePanelProvider>[
      AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
    ];
    final synchronize = controller.synchronizeProviders();
    await _flushEvents();

    expect(controller.providers.map(_providerId), <String>['grok']);
    expect(repository.requests.last.providerId, 'grok');

    staleCodex.complete(_entry('codex', 'Stale Codex'));
    repository.requests.last.complete(_entry('grok', 'Grok'));
    await Future.wait(<Future<void>>[staleRefresh, synchronize]);

    expect(controller.providers.single.entry?.providerName, 'Grok');
  });

  test('单 Provider 失败局部展示错误，并可独立重试', () async {
    final repository = _ControlledPanelRepository();
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    final initialRefresh = controller.refresh();
    await _flushEvents();
    repository.requests.single.fail();
    await initialRefresh;

    expect(
      controller.selectedProvider?.status,
      AgentUsagePanelProviderLoadStatus.failed,
    );
    expect(controller.selectedProvider?.loadError, 'Agent 用量暂时无法读取');
    expect(controller.errorMessage, isNull);

    final retry = controller.refresh();
    await _flushEvents();
    expect(repository.requests, hasLength(2));
    repository.requests.last.complete(_entry('codex', 'Codex'));
    await retry;

    expect(
      controller.selectedProvider?.status,
      AgentUsagePanelProviderLoadStatus.loaded,
    );
    expect(controller.selectedProvider?.loadError, isNull);
  });

  test('恢复偏好后首次只加载恢复的 Provider 且不回写', () async {
    final repository = _ControlledPanelRepository();
    final selectionChanges = <String?>[];
    final controller = AgentUsagePanelController(
      repository: repository,
      initialPreferredProviderId: ' grok ',
      onSelectionChanged: selectionChanges.add,
    );
    addTearDown(controller.dispose);

    final refresh = controller.refresh();
    await _flushEvents();

    expect(controller.selectedProviderId, 'grok');
    expect(repository.requests.single.providerId, 'grok');
    expect(selectionChanges, isEmpty);

    repository.requests.single.complete(_entry('grok', 'Grok'));
    await refresh;
  });

  test('目录到达前保留最后一个 Turn 终态偏好并按需加载', () async {
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

    final refresh = controller.refresh();
    await _flushEvents();

    expect(controller.selectedProviderId, 'grok');
    expect(repository.requests.single.providerId, 'grok');
    expect(selectionChanges, <String?>['codex', 'grok']);

    repository.requests.single.complete(_entry('grok', 'Grok'));
    await refresh;
  });

  test('目录读取失败时提供目录级错误并允许重试', () async {
    final repository = _ControlledPanelRepository()..failNextDiscovery = true;
    final controller = AgentUsagePanelController(repository: repository);
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.errorMessage, 'Agent 用量暂时无法读取');
    expect(controller.providers, isEmpty);

    final retry = controller.refresh();
    await _flushEvents();
    repository.requests.single.complete(_entry('codex', 'Codex'));
    await retry;

    expect(controller.errorMessage, isNull);
    expect(controller.selectedEntry?.providerId, 'codex');
  });
}

const _directory = <AgentUsagePanelProvider>[
  AgentUsagePanelProvider(providerId: 'codex', providerName: 'Codex'),
  AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
];

String _providerId(AgentUsagePanelProviderState state) =>
    state.provider.providerId;

AgentUsagePanelEntry _entry(String providerId, String providerName) =>
    AgentUsagePanelEntry(providerId: providerId, providerName: providerName);

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

final class _ControlledPanelRepository implements AgentUsagePanelRepository {
  List<AgentUsagePanelProvider> directory = _directory;
  bool failNextDiscovery = false;
  int discoverCount = 0;
  final List<_ProviderRequest> requests = <_ProviderRequest>[];

  @override
  Future<List<AgentUsagePanelProvider>> discoverProviders() async {
    discoverCount += 1;
    if (failNextDiscovery) {
      failNextDiscovery = false;
      throw StateError('sensitive directory failure');
    }
    return List<AgentUsagePanelProvider>.unmodifiable(directory);
  }

  @override
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  }) {
    final request = _ProviderRequest(
      providerId: providerId,
      forceRefresh: forceRefresh,
    );
    requests.add(request);
    return request.result.future;
  }
}

final class _ProviderRequest {
  _ProviderRequest({required this.providerId, required this.forceRefresh});

  final String providerId;
  final bool forceRefresh;
  final Completer<AgentUsagePanelProviderResult?> result =
      Completer<AgentUsagePanelProviderResult?>();

  void complete(AgentUsagePanelEntry entry) {
    result.complete(
      AgentUsagePanelProviderResult(
        entry: entry,
        refreshedAt: DateTime(2026, 8, 12, 12),
      ),
    );
  }

  void fail() {
    result.completeError(StateError('sensitive provider failure'));
  }
}
