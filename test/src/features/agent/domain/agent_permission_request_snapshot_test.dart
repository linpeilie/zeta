import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_permission_request_resolver.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentPermissionRequestSnapshot', () {
    const thread = AgentPermissionSelection(optionId: 'thread-option');
    const provider = AgentPermissionSelection(optionId: 'provider-option');
    const catalog = AgentPermissionSelection(optionId: 'catalog-option');

    test('resolves thread effective before provider and catalog defaults', () {
      final snapshot = AgentPermissionRequestResolver.resolve(
        threadEffective: thread,
        providerDefault: provider,
        catalogDefault: catalog,
      );

      expect(snapshot.selection, thread);
      expect(snapshot.source, AgentPermissionRequestSource.threadEffective);
    });

    test('resolves provider default before catalog default', () {
      final snapshot = AgentPermissionRequestResolver.resolve(
        providerDefault: provider,
        catalogDefault: catalog,
      );

      expect(snapshot.selection, provider);
      expect(snapshot.source, AgentPermissionRequestSource.providerDefault);
    });

    test('uses catalog default then explicit provider fallback', () {
      final catalogSnapshot = AgentPermissionRequestResolver.resolve(
        catalogDefault: catalog,
      );
      final fallbackSnapshot = AgentPermissionRequestResolver.resolve();

      expect(catalogSnapshot.selection, catalog);
      expect(
        catalogSnapshot.source,
        AgentPermissionRequestSource.catalogDefault,
      );
      expect(fallbackSnapshot.selection, isNull);
      expect(
        fallbackSnapshot.source,
        AgentPermissionRequestSource.providerFallback,
      );
    });

    test(
      'turn configuration keeps the immutable snapshot and mode separate',
      () {
        const snapshot = AgentPermissionRequestSnapshot.resolved(
          selection: thread,
          source: AgentPermissionRequestSource.threadEffective,
        );
        const configuration = AgentTurnConfiguration(
          permissionSnapshot: snapshot,
        );

        expect(configuration.permissionSnapshot, snapshot);
        expect(configuration.conversationMode, isNull);
        expect(
          configuration.copyWith(),
          configuration,
          reason: 'copying must preserve the same request snapshot value',
        );
      },
    );

    test(
      'domain snapshot declaration contains no provider protocol fields',
      () {
        final source = File(
          'lib/src/features/agent/domain/agent_permission_policy_models.dart',
        ).readAsStringSync();
        final start = source.indexOf(
          'final class AgentPermissionRequestSnapshot',
        );
        final end = source.indexOf('\n/// 权限选择生效范围', start);
        expect(start, isNonNegative);
        expect(end, greaterThan(start));
        final declaration = source.substring(start, end);

        for (final forbidden in const <String>[
          'approvalPolicy',
          'sandboxPolicy',
          'permission_mode',
          'yolo_mode',
        ]) {
          expect(declaration, isNot(contains(forbidden)));
        }
      },
    );
  });
}
