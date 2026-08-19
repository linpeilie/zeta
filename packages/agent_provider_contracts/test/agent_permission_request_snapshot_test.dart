import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  const selection = AgentPermissionSelection(optionId: 'ask');

  test('resolved and fallback snapshots preserve typed source semantics', () {
    const resolved = AgentPermissionRequestSnapshot.resolved(
      selection: selection,
      source: AgentPermissionRequestSource.threadEffective,
    );
    const fallback = AgentPermissionRequestSnapshot.providerFallback();
    expect(resolved.selection, selection);
    expect(resolved.source, AgentPermissionRequestSource.threadEffective);
    expect(fallback.selection, isNull);
    expect(fallback.source, AgentPermissionRequestSource.providerFallback);
  });

  test('turn configuration copy keeps separate mode and permission values', () {
    const snapshot = AgentPermissionRequestSnapshot.resolved(
      selection: selection,
      source: AgentPermissionRequestSource.localWorkflowOverride,
    );
    const configuration = AgentTurnConfiguration(
      permissionSnapshot: snapshot,
    );
    expect(configuration.copyWith(), configuration);
    expect(configuration.conversationMode, isNull);
  });

  test('plan execution permission creates the correct request snapshot', () {
    const choice = AgentPlanExecutionPermissionChoice(
      label: 'Ask',
      origin: AgentPlanExecutionPermissionOrigin.userOverride,
      selection: selection,
    );
    expect(
      choice.toRequestSnapshot().source,
      AgentPermissionRequestSource.localWorkflowOverride,
    );
    const fallbackChoice = AgentPlanExecutionPermissionChoice(
      label: 'Provider default',
      origin: AgentPlanExecutionPermissionOrigin.providerFallback,
    );
    expect(
      fallbackChoice.toRequestSnapshot().source,
      AgentPermissionRequestSource.providerFallback,
    );
  });
}
