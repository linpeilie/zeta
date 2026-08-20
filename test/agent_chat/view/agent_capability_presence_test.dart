import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zeta/agent_chat/agent_chat.dart';

import '../../helpers/helpers.dart';

class _MockAgentConversationBloc
    extends MockBloc<AgentConversationEvent, AgentConversationState>
    implements AgentConversationBloc {}

const _optionalCapabilityKeys = <Key>[
  Key('optional-capability-threadCatalog'),
  Key('optional-capability-threadSubscription'),
  Key('optional-capability-threadNaming'),
  Key('optional-capability-threadArchival'),
  Key('optional-capability-threadDeletion'),
  Key('optional-capability-threadCompaction'),
  Key('optional-capability-threadBranching'),
  Key('optional-capability-turnSteering'),
  Key('optional-capability-permissionResponses'),
  Key('optional-capability-questions'),
  Key('optional-capability-deniedActionOverride'),
  Key('optional-capability-modelCatalog'),
  Key('optional-capability-conversationModes'),
  Key('optional-capability-skills'),
  Key('optional-capability-localThreadList'),
  Key('optional-capability-sessionConfiguration'),
  Key('optional-capability-planApproval'),
  Key('optional-capability-permissionPolicy'),
  Key('optional-capability-usageQuota'),
];

void main() {
  group(AgentConversationCapabilities, () {
    late AgentConversationBloc bloc;

    setUp(() {
      bloc = _MockAgentConversationBloc();
      registerFallbackValue(const AgentConversationClosed());
    });

    testWidgets('hides every optional capability entry when ports are absent', (
      tester,
    ) async {
      when(() => bloc.state).thenReturn(const AgentConversationState());
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentConversationView()),
      );
      expect(_optionalCapabilityKeys, hasLength(19));
      for (final key in _optionalCapabilityKeys) {
        expect(find.byKey(key), findsNothing);
      }
    });

    testWidgets('shows every optional capability entry when ports exist', (
      tester,
    ) async {
      when(() => bloc.state).thenReturn(
        const AgentConversationState(
          capabilities: AgentCapabilityPresence(
            threadCatalog: true,
            threadSubscription: true,
            threadNaming: true,
            threadArchival: true,
            threadDeletion: true,
            threadCompaction: true,
            threadBranching: true,
            turnSteering: true,
            permissionResponses: true,
            questions: true,
            deniedActionOverride: true,
            modelCatalog: true,
            conversationModes: true,
            skills: true,
            localThreadList: true,
            sessionConfiguration: true,
            planApproval: true,
            permissionPolicy: true,
            usageQuota: true,
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentConversationView()),
      );
      for (final key in _optionalCapabilityKeys) {
        expect(find.byKey(key), findsOneWidget);
        await tester.tap(find.byKey(key));
      }
      await tester.pump();
    });
  });
}
