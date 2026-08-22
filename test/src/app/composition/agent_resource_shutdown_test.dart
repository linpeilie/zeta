import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/composition/agent_resource_shutdown.dart';

void main() {
  group('shutdownAgentResourcesInOrder', () {
    test('runtime registry 先关，plugin catalog 后关', () async {
      final order = <String>[];

      await shutdownAgentResourcesInOrder(
        closeRuntimeRegistry: () async {
          order.add('runtime:start');
          await Future<void>.delayed(Duration.zero);
          order.add('runtime:done');
        },
        closePluginCatalog: () async {
          order.add('plugin:start');
          await Future<void>.delayed(Duration.zero);
          order.add('plugin:done');
        },
      );

      expect(order, <String>[
        'runtime:start',
        'runtime:done',
        'plugin:start',
        'plugin:done',
      ]);
    });

    test('缺席的资源被跳过，不影响其余顺序', () async {
      final order = <String>[];

      await shutdownAgentResourcesInOrder(
        closePluginCatalog: () async => order.add('plugin'),
      );
      await shutdownAgentResourcesInOrder(
        closeRuntimeRegistry: () async => order.add('runtime'),
      );

      expect(order, <String>['plugin', 'runtime']);
    });

    test('两者都缺席时不抛异常', () async {
      await shutdownAgentResourcesInOrder();
    });
  });
}
