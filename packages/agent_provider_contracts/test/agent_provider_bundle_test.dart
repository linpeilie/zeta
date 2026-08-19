import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

final class _RuntimePort extends Mock implements AgentRuntimePort {}

final class _ConversationPort extends Mock implements AgentConversationPort {}

void main() {
  test('minimal bundle exposes required ports and conservative optionals', () {
    final runtime = _RuntimePort();
    final conversation = _ConversationPort();
    const capabilities = AgentProviderCapabilities(canPrompt: true);
    when(() => runtime.capabilities).thenReturn(capabilities);

    final bundle = AgentProviderBundle(
      runtime: runtime,
      conversation: conversation,
    );

    expect(bundle.runtime, same(runtime));
    expect(bundle.conversation, same(conversation));
    expect(bundle.capabilities, capabilities);
    expect(bundle.threadCatalog, isNull);
    expect(bundle.permissionPolicy, isNull);
    expect(bundle.usageQuota, isNull);
  });
}
