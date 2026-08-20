import 'package:app_ui/app_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  test('layout resolvers cover breakpoints and available extents', () {
    expect(resolveWorkbenchLayoutMode(819), IdeWorkbenchLayoutMode.compact);
    expect(resolveWorkbenchLayoutMode(820), IdeWorkbenchLayoutMode.medium);
    expect(resolveWorkbenchLayoutMode(1180), IdeWorkbenchLayoutMode.wide);
    expect(
      resolveEffectiveWorkbenchLayoutMode(
        width: double.infinity,
        navigationAvailable: true,
        inspectorAvailable: true,
        leadingRailAvailable: true,
        trailingRailAvailable: true,
        navigationWidth: 280,
        inspectorWidth: 300,
      ),
      IdeWorkbenchLayoutMode.wide,
    );
    expect(
      resolveEffectiveWorkbenchLayoutMode(
        width: 1180,
        navigationAvailable: true,
        inspectorAvailable: true,
        leadingRailAvailable: true,
        trailingRailAvailable: true,
        navigationWidth: 400,
        inspectorWidth: 400,
      ),
      IdeWorkbenchLayoutMode.medium,
    );
    expect(
      resolveEffectiveWorkbenchLayoutMode(
        width: 900,
        navigationAvailable: true,
        inspectorAvailable: false,
        leadingRailAvailable: false,
        trailingRailAvailable: false,
        navigationWidth: 220,
        inspectorWidth: 220,
      ),
      IdeWorkbenchLayoutMode.medium,
    );
  });

  test('constructor validates overlay inputs', () {
    final emptyLabel = StringBuffer().toString();
    final negativeWidth = double.parse('-1');
    expect(
      () => IdeWorkbenchScaffold(
        canvas: const SizedBox.shrink(),
        closeOverlaySemanticLabel: emptyLabel,
      ),
      throwsAssertionError,
    );
    expect(
      () => IdeWorkbenchScaffold(
        canvas: const SizedBox.shrink(),
        closeOverlaySemanticLabel: 'Close',
        navigationWidth: negativeWidth,
      ),
      throwsAssertionError,
    );
    expect(
      () => IdeWorkbenchScaffold(
        canvas: const SizedBox.shrink(),
        closeOverlaySemanticLabel: 'Close',
        inspectorWidth: negativeWidth,
      ),
      throwsAssertionError,
    );
    expect(
      () => IdeWorkbenchScaffold(
        canvas: const SizedBox.shrink(),
        closeOverlaySemanticLabel: emptyLabel.isEmpty ? 'Close' : emptyLabel,
        activeOverlay: IdeWorkbenchOverlay.navigation,
      ),
      throwsAssertionError,
    );
  });

  testWidgets('wide workbench renders rails, panes, handles, and canvas', (
    tester,
  ) async {
    final modes = <IdeWorkbenchLayoutMode>[];
    await tester.pumpShadcnApp(
      SizedBox(
        width: 1400,
        child: _workbench(
          leading: (context, mode) {
            modes.add(mode);
            return const Text('Leading');
          },
          trailing: (context, mode) => const Text('Trailing'),
          navigationHandle: const Text('Navigation handle'),
          inspectorHandle: const Text('Inspector handle'),
        ),
      ),
      size: const Size(1400, 600),
    );
    expect(modes, <IdeWorkbenchLayoutMode>[IdeWorkbenchLayoutMode.wide]);
    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsOneWidget,
    );
    expect(find.text('Navigation handle'), findsOneWidget);
    expect(find.text('Inspector handle'), findsOneWidget);
    expect(find.text('Canvas'), findsOneWidget);
  });

  testWidgets('medium inspector overlay dismisses by scrim and escape', (
    tester,
  ) async {
    final trigger = FocusNode();
    addTearDown(trigger.dispose);
    IdeWorkbenchOverlay? overlay = IdeWorkbenchOverlay.inspector;
    var dismissals = 0;
    late StateSetter update;
    await tester.pumpShadcnApp(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return SizedBox(
            width: 900,
            child: _workbench(
              activeOverlay: overlay,
              trigger: trigger,
              leading: (context, mode) => Focus(
                focusNode: trigger,
                child: const Text('Trigger'),
              ),
              onDismiss: () {
                dismissals += 1;
                setState(() => overlay = null);
              },
            ),
          );
        },
      ),
      size: const Size(1000, 600),
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-overlay')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Close side panel'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workbench-overlay-scrim')));
    await tester.pump();
    expect(dismissals, 1);
    expect(trigger.hasFocus, isTrue);
    expect(find.byKey(const ValueKey('workbench-overlay-stack')), findsNothing);

    update(() => overlay = IdeWorkbenchOverlay.inspector);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(dismissals, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(dismissals, 2);
    expect(
      find.byKey(const ValueKey('workbench-inspector-overlay')),
      findsNothing,
    );
  });

  testWidgets('compact workbench clamps overlays and can retain navigation', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const SizedBox(
        width: 200,
        child: IdeWorkbenchScaffold(
          canvas: Text('Canvas'),
          closeOverlaySemanticLabel: 'Close',
          trailingRailBuilder: _rail,
          navigationPane: Text('Navigation'),
          inspectorPane: Text('Inspector'),
          activeOverlay: IdeWorkbenchOverlay.navigation,
          navigationWidth: 400,
          inspectorWidth: 100,
          onDismissOverlay: _noop,
        ),
      ),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('workbench-navigation-overlay')))
          .width,
      160,
    );

    await tester.pumpShadcnApp(
      const SizedBox(
        width: 700,
        child: IdeWorkbenchScaffold(
          canvas: Text('Canvas'),
          closeOverlaySemanticLabel: 'Close',
          navigationPane: Text('Navigation'),
          inspectorPane: Text('Inspector'),
          navigationInlineInCompact: true,
          inspectorVisible: false,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-inspector-inline')),
      findsNothing,
    );
  });

  testWidgets('hidden or unavailable overlays leave only the base layout', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const SizedBox(
        width: 500,
        child: IdeWorkbenchScaffold(
          canvas: Text('Canvas'),
          closeOverlaySemanticLabel: 'Close',
          navigationPane: Text('Navigation'),
          navigationVisible: false,
          activeOverlay: IdeWorkbenchOverlay.navigation,
          onDismissOverlay: _noop,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('workbench-overlay-stack')), findsNothing);
    expect(find.byKey(const ValueKey('workbench-base')), findsOneWidget);
  });
}

IdeWorkbenchScaffold _workbench({
  IdeWorkbenchRailBuilder? leading,
  IdeWorkbenchRailBuilder? trailing,
  Widget? navigationHandle,
  Widget? inspectorHandle,
  IdeWorkbenchOverlay? activeOverlay,
  FocusNode? trigger,
  VoidCallback? onDismiss,
}) {
  return IdeWorkbenchScaffold(
    canvas: const Text('Canvas'),
    closeOverlaySemanticLabel: 'Close side panel',
    leadingRailBuilder: leading,
    trailingRailBuilder: trailing,
    navigationPane: const Text('Navigation'),
    navigationResizeHandle: navigationHandle,
    inspectorPane: const Text('Inspector'),
    inspectorResizeHandle: inspectorHandle,
    activeOverlay: activeOverlay,
    onDismissOverlay: activeOverlay == null ? null : onDismiss ?? _noop,
    overlayTriggerFocusNode: trigger,
  );
}

void _noop() {}

Widget _rail(BuildContext context, IdeWorkbenchLayoutMode mode) {
  return const SizedBox.shrink();
}
