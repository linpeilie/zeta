import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/app/router/route_reconcile_host.dart';
import 'package:zeta/src/app/router/route_reconcile_status.dart';
import 'package:zeta/src/app/router/router_coordinator.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';

const _projectPath = '/repo';
const _providers = <String>{'codex', 'grok', 'claude_code'};

final _coordinatorProvider = Provider<RouterCoordinator>(
  (ref) => throw StateError('override in test'),
);

void main() {
  late ProviderContainer container;
  late _FakeReconcileHost host;
  late _RecordingNavigationPort navigation;
  late ProjectIdMapping mapping;
  late String projectId;
  late RouterCoordinator coordinator;

  setUp(() {
    mapping = ProjectIdMapping()..syncProjects(const <String>[_projectPath]);
    projectId = mapping.idForPath(_projectPath)!;
    host = _FakeReconcileHost();
    navigation = _RecordingNavigationPort();
    container = ProviderContainer(
      overrides: [
        _coordinatorProvider.overrideWith((ref) {
          final value = RouterCoordinator(
            ref: ref,
            mapping: mapping,
            readHost: () => host,
            navigation: navigation,
            readProviderIds: () => _providers,
          );
          ref.onDispose(value.dispose);
          return value;
        }),
      ],
    );
    addTearDown(container.dispose);
    coordinator = container.read(_coordinatorProvider);
  });

  RouteReconcileStatus status() =>
      container.read(routerReconcileStatusProvider);

  test('global home and settings do not touch the shell', () async {
    expect(await coordinator.reconcile(const GlobalHomeLocation()), isTrue);
    expect(
      await coordinator.reconcile(
        const SettingsLocation(SettingsSection.general),
      ),
      isTrue,
    );
    expect(host.calls, isEmpty);
    expect(status(), const RouteReconcileIdle());
  });

  test('project home and draft delegate to the shell', () async {
    expect(await coordinator.reconcile(ProjectHomeLocation(projectId)), isTrue);
    expect(
      await coordinator.reconcile(DraftThreadLocation(projectId, 'codex')),
      isTrue,
    );
    expect(host.calls, <String>[
      'home:$_projectPath',
      'draft:$_projectPath:codex',
    ]);
    expect(status(), const RouteReconcileIdle());
  });

  test(
    'thread open success is idle; failure is failed without navigating',
    () async {
      expect(
        await coordinator.reconcile(ThreadLocation(projectId, 'tid')),
        isTrue,
      );
      expect(host.calls, <String>['thread:$_projectPath:tid']);

      host.openThreadResult = false;
      final location = ThreadLocation(projectId, 'missing');
      expect(await coordinator.reconcile(location), isFalse);
      expect(
        status(),
        RouteReconcileFailed(
          location,
          RouteReconcileReason.conversationOpenFailed,
        ),
      );
      expect(navigation.goes, isEmpty);
    },
  );

  test('unknown projectId navigates home and marks failed', () async {
    const location = ProjectHomeLocation('deadbeefdead');
    expect(await coordinator.reconcile(location), isFalse);
    expect(host.calls, isEmpty);
    expect(navigation.goes, const <AppRouteLocation>[GlobalHomeLocation()]);
    expect(
      status(),
      const RouteReconcileFailed(
        location,
        RouteReconcileReason.projectUnavailable,
      ),
    );
  });

  test('unregistered providerId falls back to project home', () async {
    final location = DraftThreadLocation(projectId, 'not-a-provider');
    expect(await coordinator.reconcile(location), isFalse);
    expect(host.calls, isEmpty);
    expect(navigation.goes, <AppRouteLocation>[ProjectHomeLocation(projectId)]);
    expect(
      status(),
      RouteReconcileFailed(location, RouteReconcileReason.providerUnavailable),
    );
  });

  test('same location is idempotent after success', () async {
    final location = ProjectHomeLocation(projectId);
    expect(await coordinator.reconcile(location), isTrue);
    host.calls.clear();
    expect(await coordinator.reconcile(location), isTrue);
    expect(host.calls, isEmpty);
  });

  test('a newer location invalidates an in-flight reconcile', () async {
    host.gate = Completer<void>();
    host.entered = Completer<void>();
    final first = coordinator.reconcile(ProjectHomeLocation(projectId));
    await host.entered!.future;
    expect(status(), RouteReconcileOpening(ProjectHomeLocation(projectId)));

    host.entered = Completer<void>();
    final second = coordinator.reconcile(
      DraftThreadLocation(projectId, 'codex'),
    );
    await host.entered!.future;
    host.gate!.complete();
    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(host.calls, <String>[
      'home:$_projectPath',
      'draft:$_projectPath:codex',
    ]);
    expect(status(), const RouteReconcileIdle());
  });

  test('host exceptions become failed status', () async {
    host.throwOnOpen = StateError('open failed');
    final location = ThreadLocation(projectId, 'tid');
    expect(await coordinator.reconcile(location), isFalse);
    expect(
      status(),
      RouteReconcileFailed(
        location,
        RouteReconcileReason.conversationOpenFailed,
      ),
    );
  });
}

final class _FakeReconcileHost implements RouteReconcileHost {
  final List<String> calls = <String>[];
  Completer<void>? gate;
  Completer<void>? entered;
  bool openThreadResult = true;
  Object? throwOnOpen;

  @override
  Future<void> openProjectHomeFromRoute(String projectPath) async {
    calls.add('home:$projectPath');
    await _wait();
  }

  @override
  Future<void> startNewThreadForProject(
    String projectPath, {
    required String providerId,
  }) async {
    calls.add('draft:$projectPath:$providerId');
    await _wait();
  }

  @override
  Future<bool> openThreadFromRoute(String projectPath, String threadId) async {
    calls.add('thread:$projectPath:$threadId');
    await _wait();
    final error = throwOnOpen;
    if (error != null) {
      throw error;
    }
    return openThreadResult;
  }

  Future<void> _wait() async {
    entered?.complete();
    final current = gate;
    if (current != null) {
      await current.future;
    }
  }
}

final class _RecordingNavigationPort implements AppNavigationPort {
  final List<AppRouteLocation> goes = <AppRouteLocation>[];
  final List<AppRouteLocation> replaces = <AppRouteLocation>[];

  @override
  void go(AppRouteLocation location) => goes.add(location);

  @override
  void replace(AppRouteLocation location) => replaces.add(location);
}
