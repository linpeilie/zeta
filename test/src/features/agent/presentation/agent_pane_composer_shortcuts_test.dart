import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

import 'harness/agent_pane_test_harness.dart';

void main() {
  group('AgentPane composer shortcuts', () {
    testWidgets('Enter sends once by default and clears the draft', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);
      final input = find.byKey(const ValueKey('agent-message-input'));

      await tester.enterText(input, 'Send with Enter');
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(provider.sentMessages, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await pumpUntilMessageSent(tester, provider);

      expect(provider.sentMessages, <String>['Send with Enter']);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        isEmpty,
      );
      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await tester.pump();
    });

    testWidgets('numpad Enter uses the active send shortcut', (tester) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);
      final input = find.byKey(const ValueKey('agent-message-input'));

      await tester.enterText(input, 'Send with numpad');
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await pumpUntilMessageSent(tester, provider);

      expect(provider.sentMessages, <String>['Send with numpad']);
      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await tester.pump();
    });

    testWidgets('Shift Enter inserts a newline without sending', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);
      final input = find.byKey(const ValueKey('agent-message-input'));

      await tester.enterText(input, 'First line');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(provider.sentMessages, isEmpty);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'First line\n',
      );
    });

    testWidgets('Ctrl Enter mode keeps plain Enter for newline and sends', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          messageSendShortcut: MessageSendShortcut.primaryModifierEnter,
          platform: TargetPlatform.windows,
        ),
      );
      await pumpAgentPaneUi(tester);
      final input = find.byKey(const ValueKey('agent-message-input'));

      await tester.enterText(input, 'First line');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(provider.sentMessages, isEmpty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await pumpUntilMessageSent(tester, provider);

      expect(provider.sentMessages, hasLength(1));
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        isEmpty,
      );
      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await tester.pump();
    });

    testWidgets('macOS requires Command Enter instead of Ctrl Enter', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: viewModel,
          messageSendShortcut: MessageSendShortcut.primaryModifierEnter,
          platform: TargetPlatform.macOS,
        ),
      );
      await pumpAgentPaneUi(tester);
      final input = find.byKey(const ValueKey('agent-message-input'));

      await tester.enterText(input, 'Send on macOS');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(provider.sentMessages, isEmpty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await pumpUntilMessageSent(tester, provider);

      expect(provider.sentMessages, hasLength(1));
      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await tester.pump();
    });

    testWidgets('Enter does not send while IME composition is active', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);
      final input = find.byKey(const ValueKey('agent-message-input'));
      await tester.tap(input);
      await tester.pump();
      final editable = tester.widget<EditableText>(
        find.descendant(of: input, matching: find.byType(EditableText)),
      );
      editable.controller.value = const TextEditingValue(
        text: '拼',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(provider.sentMessages, isEmpty);
    });

    testWidgets('send shortcut does nothing for empty or unavailable input', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider(canSteerTurn: false);
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);
      final input = find.byKey(const ValueKey('agent-message-input'));

      await tester.tap(input);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(provider.sentMessages, isEmpty);

      await viewModel.sendMessage('Already running');
      await pumpLiveAgentUi(tester);
      expect(viewModel.canSubmitMessage, isFalse);
      await tester.enterText(input, 'Keep this draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(provider.sentMessages, <String>['Already running']);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'Keep this draft',
      );
      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await tester.pump();
    });
  });
}
