import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentPermissionCatalogController', () {
    test(
      'retains the complete last-known-good catalog after transient failure',
      () async {
        var calls = 0;
        final catalog = _catalog('team-safe', label: 'Team safe');
        final controller = AgentPermissionCatalogController();
        addTearDown(controller.dispose);
        controller.bind(
          _FakePermissionPort(() async {
            calls += 1;
            if (calls == 1) {
              return catalog;
            }
            throw TimeoutException('catalog refresh timed out');
          }),
        );

        expect(await controller.refresh(), isTrue);
        expect(controller.catalog, same(catalog));

        expect(await controller.refresh(), isTrue);
        expect(controller.catalog, same(catalog));
        expect(controller.options.single.label, 'Team safe');
        expect(controller.catalogDefault?.optionId, 'team-safe');
        expect(controller.lastError, isA<TimeoutException>());
        expect(controller.isLoading, isFalse);
      },
    );

    test(
      'commits an empty successful catalog instead of guessing failure',
      () async {
        final responses = <AgentPermissionCatalog>[
          _catalog('team-safe'),
          AgentPermissionCatalog(
            options: const <AgentPermissionOption>[],
            defaultOptionId: '',
          ),
        ];
        final controller = AgentPermissionCatalogController();
        addTearDown(controller.dispose);
        controller.bind(_FakePermissionPort(() async => responses.removeAt(0)));

        await controller.refresh();
        expect(controller.options, isNotEmpty);

        await controller.refresh();
        expect(controller.options, isEmpty);
        expect(controller.catalogDefault, isNull);
        expect(controller.lastError, isNull);
      },
    );

    test(
      'a superseded refresh cannot overwrite a newer complete catalog',
      () async {
        final first = Completer<AgentPermissionCatalog>();
        final second = Completer<AgentPermissionCatalog>();
        var calls = 0;
        final controller = AgentPermissionCatalogController();
        addTearDown(controller.dispose);
        controller.bind(
          _FakePermissionPort(() {
            calls += 1;
            return calls == 1 ? first.future : second.future;
          }),
        );

        final firstRefresh = controller.refresh();
        final secondRefresh = controller.refresh();
        expect(controller.isLoading, isTrue);

        final newer = _catalog('newer');
        second.complete(newer);
        expect(await secondRefresh, isTrue);
        expect(controller.catalog, same(newer));

        first.complete(_catalog('older'));
        expect(await firstRefresh, isFalse);
        expect(controller.catalog, same(newer));
        expect(controller.isLoading, isFalse);
      },
    );

    test(
      'binding a different port clears the previous provider catalog',
      () async {
        final controller = AgentPermissionCatalogController();
        addTearDown(controller.dispose);
        final firstPort = _FakePermissionPort(() async => _catalog('first'));
        controller.bind(firstPort);
        await controller.refresh();
        expect(controller.options.single.id, 'first');

        controller.bind(_FakePermissionPort(() async => _catalog('second')));

        expect(controller.catalog, isNull);
        expect(controller.options, isEmpty);
        expect(controller.lastError, isNull);
      },
    );

    test(
      'same provider rebind keeps stale catalog until the new port refreshes',
      () async {
        final controller = AgentPermissionCatalogController();
        addTearDown(controller.dispose);
        controller.bind(_FakePermissionPort(() async => _catalog('global')));
        await controller.refresh();

        controller.bind(
          _FakePermissionPort(() async => _catalog('session')),
          preserveLastKnownGood: true,
        );

        expect(controller.options.single.id, 'global');
        expect(controller.catalogDefault?.optionId, 'global');

        await controller.refresh();

        expect(controller.options.single.id, 'session');
        expect(controller.catalogDefault?.optionId, 'session');
      },
    );

    test(
      'same provider rebind retains stale catalog when the new port fails',
      () async {
        final controller = AgentPermissionCatalogController();
        addTearDown(controller.dispose);
        controller.bind(_FakePermissionPort(() async => _catalog('global')));
        await controller.refresh();

        controller.bind(
          _FakePermissionPort(
            () async => throw TimeoutException('session catalog timed out'),
          ),
          preserveLastKnownGood: true,
        );
        await controller.refresh();

        expect(controller.options.single.id, 'global');
        expect(controller.catalogDefault?.optionId, 'global');
        expect(controller.lastError, isA<TimeoutException>());
      },
    );
  });
}

AgentPermissionCatalog _catalog(String id, {String? label}) {
  return AgentPermissionCatalog(
    options: <AgentPermissionOption>[
      AgentPermissionOption(id: id, label: label ?? id),
    ],
    defaultOptionId: id,
  );
}

final class _FakePermissionPort implements AgentPermissionPolicyPort {
  const _FakePermissionPort(this.load);

  final Future<AgentPermissionCatalog> Function() load;

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() => load();

  @override
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    return AgentPermissionApplyResult(
      normalizedSelection: selection,
      scope: AgentPermissionApplyScope.currentSession,
    );
  }
}
