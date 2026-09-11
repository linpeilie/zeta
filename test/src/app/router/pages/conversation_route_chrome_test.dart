import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/router/pages/conversation_route_chrome.dart';

import '../../../ui/core/ide_component_test_harness.dart';

void main() {
  testWidgets('skeleton hides the spinner until it is armed', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const ConversationSkeletonPage(
        title: 'Opening conversation',
        showSpinner: false,
      ),
    );

    expect(find.byKey(const ValueKey('conversation-skeleton')), findsOneWidget);
    expect(find.text('Opening conversation'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-open-spinner')),
      findsNothing,
    );
  });

  testWidgets('skeleton shows the spinner when armed', (tester) async {
    await pumpIdeComponent(
      tester,
      child: const ConversationSkeletonPage(
        title: 'Opening conversation',
        showSpinner: true,
      ),
    );

    expect(
      find.byKey(const ValueKey('conversation-open-spinner')),
      findsOneWidget,
    );
  });

  testWidgets('failed page back button notifies the caller', (tester) async {
    var backCount = 0;
    await pumpIdeComponent(
      tester,
      child: ConversationOpenFailedPage(onBack: () => backCount += 1),
    );

    expect(
      find.byKey(const ValueKey('conversation-open-failed')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('conversation-open-failed-back')),
    );
    await tester.pump();
    expect(backCount, 1);
  });
}
