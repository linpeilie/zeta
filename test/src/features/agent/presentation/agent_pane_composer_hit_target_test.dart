import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'harness/agent_pane_test_harness.dart';

void main() {
  group('AgentPane composer hit target', () {
    testWidgets('card padding focuses the field and keeps IME focus on press', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      final input = find.byKey(const ValueKey('agent-message-input'));
      final focusNode = _composerFocusNode(tester, input);
      expect(focusNode.hasFocus, isFalse);

      final paddingTap = _cardPaddingOffset(tester, input);
      await tester.tapAt(paddingTap);
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      final gesture = await tester.startGesture(paddingTap);
      await tester.pump();
      expect(
        focusNode.hasFocus,
        isTrue,
        reason: 'pointer down on card padding must not blur the field',
      );
      await gesture.up();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('toolbar controls still win over the card hit target', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      final input = find.byKey(const ValueKey('agent-message-input'));
      await tester.enterText(input, 'Send from button');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('agent-send-button')));
      await pumpUntilMessageSent(tester, provider);
      expect(provider.sentMessages, <String>['Send from button']);
      provider.emitEvent(
        const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('agent-more-actions-button')));
      await tester.pump(IdeMotion.durationSlow);
      expect(
        find.byKey(const ValueKey('agent-more-actions-popover')),
        findsOneWidget,
      );
    });

    testWidgets('composer card uses the text cursor and default tap region', (
      tester,
    ) async {
      final provider = AgentPaneFakeProvider();
      final viewModel = createAgentPaneViewModel(provider);
      addTearDown(provider.dispose);
      addTearDown(viewModel.dispose);
      await tester.pumpWidget(AgentPaneTestApp(viewModel: viewModel));
      await pumpAgentPaneUi(tester);

      final hitTarget = find.byKey(const ValueKey('agent-composer-hit-target'));
      expect(
        tester.widget<MouseRegion>(hitTarget).cursor,
        SystemMouseCursors.text,
      );
      final tapRegion = tester.widget<TextFieldTapRegion>(
        find.ancestor(
          of: find.byKey(const ValueKey('agent-composer-focus-ring')),
          matching: find.byType(TextFieldTapRegion),
        ),
      );
      expect(tapRegion.groupId, EditableText);
    });
  });
}

FocusNode _composerFocusNode(WidgetTester tester, Finder input) {
  return tester
      .widget<EditableText>(
        find.descendant(of: input, matching: find.byType(EditableText)),
      )
      .focusNode;
}

Offset _cardPaddingOffset(WidgetTester tester, [Finder? input]) {
  final card = tester.getRect(
    find.byKey(const ValueKey('agent-composer-focus-ring')),
  );
  final field = tester.getRect(
    input ?? find.byKey(const ValueKey('agent-message-input')),
  );
  final tap = Offset(card.center.dx, (card.top + field.top) / 2);
  expect(tap.dy, greaterThan(card.top));
  expect(tap.dy, lessThan(field.top));
  return tap;
}
