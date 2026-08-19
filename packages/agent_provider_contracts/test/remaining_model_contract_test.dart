import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  test(
    'permission values cover lookup, diagnostics, and equality branches',
    () {
      const option = AgentPermissionOption(
        id: 'ask',
        label: 'Ask',
        description: 'Confirm each action',
        allowed: false,
        planningOnly: true,
      );
      expect(option.toString(), contains('planningOnly: true'));
      final catalog = AgentPermissionCatalog(
        options: const <AgentPermissionOption>[option],
        defaultOptionId: 'ask',
      );
      expect(catalog.optionById(' ask '), option);
      expect(catalog.optionById(' '), isNull);
      expect(catalog.optionById('missing'), isNull);
      expect(catalog.hashCode, isNot(0));
      expect(catalog, isNot('not a catalog'));
      expect(
        catalog,
        isNot(
          AgentPermissionCatalog(
            options: const <AgentPermissionOption>[],
            defaultOptionId: 'ask',
          ),
        ),
      );
      expect(
        catalog,
        isNot(
          AgentPermissionCatalog(
            options: const <AgentPermissionOption>[
              AgentPermissionOption(id: 'other', label: 'Other'),
            ],
            defaultOptionId: 'ask',
          ),
        ),
      );
      const selection = AgentPermissionSelection(optionId: 'ask');
      expect(selection.toString(), contains('ask'));
      expect(selection.hashCode, 'ask'.hashCode);
      const snapshot = AgentPermissionRequestSnapshot.resolved(
        selection: selection,
        source: AgentPermissionRequestSource.providerDefault,
      );
      expect(snapshot.toString(), contains('providerDefault'));
      expect(snapshot.hashCode, isNot(0));
      expect(
        snapshot,
        const AgentPermissionRequestSnapshot.resolved(
          selection: selection,
          source: AgentPermissionRequestSource.providerDefault,
        ),
      );
      const result = AgentPermissionApplyResult(
        normalizedSelection: selection,
        scope: AgentPermissionApplyScope.runtime,
        warningCode: AgentPermissionWarningCode.downgradedByRuntime,
      );
      expect(result.hashCode, isNot(0));
      expect(
        result,
        const AgentPermissionApplyResult(
          normalizedSelection: selection,
          scope: AgentPermissionApplyScope.runtime,
          warningCode: AgentPermissionWarningCode.downgradedByRuntime,
        ),
      );
    },
  );

  test(
    'plan, permission, input, usage, and session models freeze collections',
    () {
      final permission = AgentPermissionRequest(
        id: 'request',
        title: 'Request',
        kind: AgentPermissionKind.commandExecution,
        fileChanges: <String, Object?>{
          'nested': <Object?>[1],
        },
        commandActions: <String>['run'],
        proposedExecpolicyAmendment: <String>['allow'],
        raw: <String, Object?>{'x': 1},
      );
      expect(permission.commandActions.clear, throwsUnsupportedError);
      final decision = AgentPermissionDecision(
        requestId: 'request',
        approved: true,
        execpolicyAmendment: <String>['allow'],
      );
      expect(
        decision.execpolicyAmendment.clear,
        throwsUnsupportedError,
      );
      expect(
        const AgentDeniedActionOverrideRequest(
          threadId: 'thread',
          requestId: 'request',
        ).threadId,
        'thread',
      );

      final phase = AgentPlanApprovalPhase(
        name: 'Phase',
        todos: const <AgentPlanEntry>[AgentPlanEntry(content: 'Do')],
      );
      final request = AgentPlanApprovalRequest(
        id: 'plan',
        title: 'Plan',
        markdown: 'Do',
        phases: <AgentPlanApprovalPhase>[phase],
        todos: const <AgentPlanEntry>[AgentPlanEntry(content: 'Do')],
        raw: <String, Object?>{'x': 1},
      );
      expect(request.phases.clear, throwsUnsupportedError);
      expect(
        const AgentPlanApprovalDecision(
          requestId: 'plan',
          kind: AgentPlanApprovalDecisionKind.accepted,
        ).kind,
        AgentPlanApprovalDecisionKind.accepted,
      );
      const choice = AgentPlanExecutionPermissionChoice(
        label: 'Ask',
        origin: AgentPlanExecutionPermissionOrigin.beforePlan,
        selection: AgentPermissionSelection(optionId: 'ask'),
      );
      const execution = AgentPlanExecutionRequest(
        id: 'execution',
        sessionId: 'thread',
        turnId: 'turn',
        title: 'Execute',
        markdown: 'Do',
        messageId: 'message',
      );
      expect(
        execution.copyWithExecutionPermission(choice).executionPermission,
        choice,
      );

      final text = AgentUserInput.text(
        'hello',
        textElements: <AgentTextElement>[
          const AgentTextElement(start: 0, end: 1),
        ],
      );
      expect((text as AgentTextUserInput).text, 'hello');
      expect(text.textElements.clear, throwsUnsupportedError);
      expect(
        (const AgentUserInput.localImage(
          path: '/image',
        ) as AgentLocalImageUserInput).path,
        '/image',
      );
      expect(
        (const AgentUserInput.mention(
          name: 'file',
          path: '/file',
        ) as AgentMentionUserInput).name,
        'file',
      );

      final quota = AgentUsageQuotaSnapshot(
        providerId: 'provider',
        providerName: 'Provider',
        windows: const <AgentUsageWindow>[
          AgentUsageWindow(label: 'Daily', usedPercent: 20),
        ],
        credits: const AgentUsageCredits(hasCredits: true, unlimited: false),
      );
      expect(quota.windows.single.usedPercent, 20);
      expect(quota.windows.clear, throwsUnsupportedError);
      final session = AgentSession(
        id: 'thread',
        providerId: 'provider',
        raw: <String, Object?>{'x': 1},
      );
      final turn = AgentTurn(
        id: 'turn',
        sessionId: session.id,
        raw: <String, Object?>{'x': 1},
      );
      expect(turn.sessionId, 'thread');
    },
  );

  test('session configuration copy and every option kind are tolerant', () {
    final value = AgentSessionConfigValue(
      id: 'one',
      label: 'One',
      raw: <String, Object?>{
        'nested': <Object?>[1],
      },
    );
    final option = AgentSessionConfigOption(
      id: 'mode',
      name: 'Mode',
      kind: AgentSessionConfigOptionKind.select,
      currentValue: 'one',
      values: <AgentSessionConfigValue>[value],
      raw: <String, Object?>{'x': 1},
    );
    final copy = option.copyWith(
      id: 'copy',
      name: 'Copy',
      kind: AgentSessionConfigOptionKind.string,
      description: 'Description',
      category: 'Category',
      currentValue: null,
      values: <AgentSessionConfigValue>[],
      raw: <String, Object?>{'y': 2},
    );
    expect(copy.currentValue, isNull);
    expect(option.copyWith().currentValue, 'one');
    for (final entry in <String, AgentSessionConfigOptionKind>{
      'boolean': AgentSessionConfigOptionKind.boolean,
      'string': AgentSessionConfigOptionKind.string,
      'number': AgentSessionConfigOptionKind.number,
      'future': AgentSessionConfigOptionKind.unknown,
    }.entries) {
      expect(
        AgentSessionConfigOption.tryDecode(<String, Object?>{
          'id': entry.key,
          'name': entry.key,
          'type': entry.key,
        })?.kind,
        entry.value,
      );
    }
    expect(
      AgentSessionConfigOption.tryDecode(<String, Object?>{
        'id': 'select',
        'name': 'Select',
        'type': 'select',
        'values': <Object?>[
          null,
          <String, Object?>{'id': null, 'label': 'Missing'},
          <String, Object?>{'id': 'ok', 'label': 'Okay'},
        ],
      })?.values.single.id,
      'ok',
    );
  });

  test('skill values provide complete equality and filtering semantics', () {
    const skill = AgentSkillMetadata(
      name: 'name',
      path: '/skill',
      description: 'description',
      enabled: true,
      displayName: 'Display',
      shortDescription: 'Short',
      defaultPrompt: 'Prompt',
      scope: 'user',
    );
    expect(
      skill,
      const AgentSkillMetadata(
        name: 'name',
        path: '/skill',
        description: 'description',
        enabled: true,
        displayName: 'Display',
        shortDescription: 'Short',
        defaultPrompt: 'Prompt',
        scope: 'user',
      ),
    );
    expect(skill.hashCode, isNot(0));
    final entry = AgentSkillsCatalogEntry(
      cwd: '/repo',
      skills: const <AgentSkillMetadata>[skill],
      errors: const <String>['warning'],
    );
    expect(
      entry,
      AgentSkillsCatalogEntry(
        cwd: '/repo',
        skills: const <AgentSkillMetadata>[skill],
        errors: const <String>['warning'],
      ),
    );
    expect(entry.hashCode, isNot(0));
    final catalog = AgentSkillsCatalog(
      entries: <AgentSkillsCatalogEntry>[entry],
    );
    expect(catalog.query('display'), <AgentSkillMetadata>[skill]);
    expect(catalog.query('short'), <AgentSkillMetadata>[skill]);
    expect(
      catalog,
      AgentSkillsCatalog(entries: <AgentSkillsCatalogEntry>[entry]),
    );
    expect(catalog.hashCode, isNot(0));
    const ref = AgentSkillRef(
      name: 'name',
      path: '/skill',
      displayName: 'Display',
    );
    expect(
      ref,
      const AgentSkillRef(name: 'name', path: '/skill', displayName: 'Display'),
    );
    expect(ref.hashCode, isNot(0));
  });
}
