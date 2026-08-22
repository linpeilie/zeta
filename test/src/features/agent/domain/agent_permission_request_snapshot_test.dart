import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

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
  });
}
