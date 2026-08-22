import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentProviderEventListenerGate', () {
    const runtime1 = AgentRuntimeScope(
      runtimeId: 'runtime-1',
      connectionEpoch: 1,
    );
    const runtime2 = AgentRuntimeScope(
      runtimeId: 'runtime-2',
      connectionEpoch: 2,
    );

    test('新 listener generation 会立即隔离旧 listener', () {
      final gate = AgentProviderEventListenerGate();
      final oldScope = gate.activate(
        providerId: 'codex',
        threadId: 'thread-old',
        runtimeScope: runtime1,
      );
      final currentScope = gate.activate(
        providerId: 'codex',
        threadId: 'thread-current',
        runtimeScope: runtime1,
      );

      expect(
        currentScope.listenerGeneration,
        greaterThan(oldScope.listenerGeneration),
      );
      expect(gate.accepts(oldScope, currentRuntimeScope: runtime1), isFalse);
      expect(gate.accepts(currentScope, currentRuntimeScope: runtime1), isTrue);
    });

    test('旧 listener 退出不能清空新 generation', () {
      final gate = AgentProviderEventListenerGate();
      final oldScope = gate.activate(
        providerId: 'codex',
        threadId: 'thread-1',
        runtimeScope: runtime1,
      );
      final currentScope = gate.activate(
        providerId: 'codex',
        threadId: 'thread-2',
        runtimeScope: runtime1,
      );

      expect(gate.release(oldScope), isFalse);
      expect(gate.current, same(currentScope));
      expect(gate.release(currentScope), isTrue);
      expect(gate.current, isNull);
    });

    test('未绑定 scope 只接受首个 runtime，后续 epoch 变化被拒绝', () {
      final gate = AgentProviderEventListenerGate();
      final scope = gate.activate(
        providerId: 'codex',
        threadId: 'thread-1',
        runtimeScope: null,
      );

      expect(gate.accepts(scope, currentRuntimeScope: runtime1), isTrue);
      expect(scope.runtimeScope, runtime1);
      expect(gate.accepts(scope, currentRuntimeScope: runtime2), isFalse);
    });

    test('仅显式关键收尾事件可在 runtime 已脱离时通过', () {
      final gate = AgentProviderEventListenerGate();
      final scope = gate.activate(
        providerId: 'codex',
        threadId: 'thread-1',
        runtimeScope: runtime1,
      );

      expect(gate.accepts(scope, currentRuntimeScope: null), isFalse);
      expect(
        gate.accepts(
          scope,
          currentRuntimeScope: null,
          allowDetachedRuntime: true,
        ),
        isTrue,
      );
      expect(
        gate.accepts(
          scope,
          currentRuntimeScope: runtime2,
          allowDetachedRuntime: true,
        ),
        isFalse,
      );
    });
  });
}
