import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/presentation/agent_flutter_listenable_adapter.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentFlutterListenableAdapter', () {
    test('转发订阅和退订但不拥有内核 signal', () {
      final source = AgentValueNotifier<int>(0);
      final adapter = AgentFlutterListenableAdapter(source);
      var notifications = 0;
      void listener() => notifications += 1;

      adapter.addListener(listener);
      source.value = 1;
      adapter.removeListener(listener);
      source.value = 2;

      expect(notifications, 1);
      expect(source.value, 2);
      source.dispose();
    });

    test('value adapter 暴露快照且相同 source 具有稳定身份', () {
      final source = AgentValueNotifier<String>('before');
      final first = AgentFlutterValueListenableAdapter<String>(source);
      final second = AgentFlutterValueListenableAdapter<String>(source);

      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
      expect(first, isA<ValueListenable<String>>());
      expect(first.value, 'before');

      source.value = 'after';

      expect(first.value, 'after');
      source.dispose();
    });
  });
}
