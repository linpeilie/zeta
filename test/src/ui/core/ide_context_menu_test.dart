import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('IdeContextMenu 支持方向键导航并跳过禁用项', (tester) async {
    var firstPresses = 0;
    var disabledPresses = 0;
    var lastPresses = 0;

    await pumpIdeComponent(
      tester,
      child: Center(
        child: IdeContextMenu(
          closeOnActivate: false,
          actions: <IdeContextMenuAction>[
            IdeContextMenuAction(
              key: const ValueKey('first-action'),
              label: 'First',
              onPressed: () => firstPresses += 1,
            ),
            IdeContextMenuAction(
              key: const ValueKey('disabled-action'),
              label: 'Disabled',
              enabled: false,
              onPressed: () => disabledPresses += 1,
            ),
            IdeContextMenuAction(
              key: const ValueKey('last-action'),
              label: 'Last',
              onPressed: () => lastPresses += 1,
            ),
          ],
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(firstPresses, 0);
    expect(disabledPresses, 0);
    expect(lastPresses, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(firstPresses, 1);
    expect(disabledPresses, 0);
    expect(lastPresses, 1);
  });

  testWidgets('IdeContextMenu 集中映射密度、分隔、语义与操作状态', (tester) async {
    final semantics = tester.ensureSemantics();
    var disabledPresses = 0;

    await pumpIdeComponent(
      tester,
      child: Center(
        child: SizedBox(
          width: 156,
          child: IdeContextMenu(
            key: const ValueKey('context-menu'),
            actions: <IdeContextMenuAction>[
              IdeContextMenuAction(
                key: const ValueKey('semantic-action'),
                label: 'Open',
                semanticLabel: 'Open workspace file',
                dividerAbove: true,
                onPressed: () {},
              ),
              IdeContextMenuAction(
                key: const ValueKey('disabled-action'),
                label: 'Disabled',
                enabled: false,
                dividerAbove: true,
                onPressed: () => disabledPresses += 1,
              ),
              IdeContextMenuAction(
                key: const ValueKey('destructive-action'),
                label:
                    'Delete a workspace entry with a deliberately long label',
                destructive: true,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final menu = tester.widget<IdeContextMenu>(
      find.byKey(const ValueKey('context-menu')),
    );
    expect(menu.minWidth, 156);
    expect(menu.closeOnActivate, isTrue);
    expect(find.byType(sf.MenuGroup), findsOneWidget);
    expect(find.byType(sf.MenuButton), findsNWidgets(3));
    expect(find.byType(sf.MenuDivider), findsOneWidget);
    expect(find.byType(sf.MenuPopup), findsNothing);
    expect(find.byType(IdeSurface), findsOneWidget);
    expect(
      tester.widget<IdeSurface>(find.byType(IdeSurface)).level,
      IdeSurfaceLevel.popover,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('semantic-action'))).height,
      32,
    );
    expect(find.bySemanticsLabel('Open workspace file'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('disabled-action')));
    await tester.pump();

    expect(disabledPresses, 0);
    final colors = IdeColors.of(
      tester.element(find.byKey(const ValueKey('context-menu'))),
    );
    final destructiveLabel = tester.widget<Text>(
      find.text('Delete a workspace entry with a deliberately long label'),
    );
    expect(destructiveLabel.style?.color, colors.error);
    expect(destructiveLabel.maxLines, 1);
    expect(destructiveLabel.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
    testWidgets('IdeContextMenu 在 ${themeMode.name} 下只保留 Graphite 表面', (
      tester,
    ) async {
      await pumpIdeComponent(
        tester,
        themeMode: themeMode,
        child: Center(
          child: IdeContextMenu(
            actions: <IdeContextMenuAction>[
              IdeContextMenuAction(label: 'Action', onPressed: () {}),
            ],
          ),
        ),
      );

      expect(find.byType(IdeSurface), findsOneWidget);
      expect(find.byType(sf.MenuPopup), findsNothing);
      expect(find.byType(sf.ModalContainer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('closeOnActivate 先移除弹层再执行 action 并回焦 trigger', (tester) async {
    var presses = 0;
    await pumpIdeComponent(
      tester,
      child: _ContextMenuOverlayHarness(
        actions: <IdeContextMenuAction>[
          IdeContextMenuAction(
            key: const ValueKey('closing-action'),
            label: 'Close and run',
            onPressed: () => presses += 1,
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('context-menu-trigger')));
    await _pumpPopover(tester);
    expect(find.byKey(const ValueKey('context-menu-popover')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('closing-action')));
    await _pumpPopover(tester);

    expect(presses, 1);
    expect(find.byKey(const ValueKey('context-menu-popover')), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'context-menu-trigger',
    );
  });

  testWidgets('closeOnActivate false 保留弹层且支持 Esc、外点与 trigger toggle', (
    tester,
  ) async {
    var presses = 0;
    await pumpIdeComponent(
      tester,
      child: _ContextMenuOverlayHarness(
        closeOnActivate: false,
        actions: <IdeContextMenuAction>[
          IdeContextMenuAction(
            key: const ValueKey('persistent-action'),
            label: 'Keep open',
            onPressed: () => presses += 1,
          ),
        ],
      ),
    );

    final trigger = find.byKey(const ValueKey('context-menu-trigger'));
    final popover = find.byKey(const ValueKey('context-menu-popover'));
    await tester.tap(trigger);
    await _pumpPopover(tester);
    await tester.tap(find.byKey(const ValueKey('persistent-action')));
    await tester.pump();

    expect(presses, 1);
    expect(popover, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpPopover(tester);
    expect(popover, findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'context-menu-trigger',
    );

    await tester.tap(trigger);
    await _pumpPopover(tester);
    expect(popover, findsOneWidget);
    await tester.tap(trigger);
    await _pumpPopover(tester);
    expect(popover, findsNothing);

    await tester.tap(trigger);
    await _pumpPopover(tester);
    expect(popover, findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await _pumpPopover(tester);
    expect(popover, findsNothing);
  });
}

class _ContextMenuOverlayHarness extends StatefulWidget {
  const _ContextMenuOverlayHarness({
    required this.actions,
    this.closeOnActivate = true,
  });

  final List<IdeContextMenuAction> actions;
  final bool closeOnActivate;

  @override
  State<_ContextMenuOverlayHarness> createState() =>
      _ContextMenuOverlayHarnessState();
}

class _ContextMenuOverlayHarnessState
    extends State<_ContextMenuOverlayHarness> {
  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'context-menu-trigger',
  );
  IdePopoverHandle<void>? _entry;

  @override
  void dispose() {
    _entry?.dismiss();
    _triggerFocusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    final entry = _entry;
    if (entry != null) {
      entry.dismiss();
      return;
    }
    final nextEntry = showIdePopover<void>(
      context: context,
      alignment: Alignment.topLeft,
      anchorAlignment: Alignment.bottomLeft,
      key: const ValueKey('context-menu-popover'),
      showDuration: const Duration(milliseconds: 1),
      dismissDuration: const Duration(milliseconds: 1),
      builder: (context) => IdeContextMenu(
        closeOnActivate: widget.closeOnActivate,
        actions: widget.actions,
      ),
    );
    _entry = nextEntry;
    setState(() {});
    unawaited(
      nextEntry.future.whenComplete(() {
        if (!mounted || !identical(_entry, nextEntry)) {
          return;
        }
        _entry = null;
        setState(() {});
        _triggerFocusNode.requestFocus();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PaneInteractiveSurface(
        key: const ValueKey('context-menu-trigger'),
        focusNode: _triggerFocusNode,
        onPressed: _toggle,
        width: 96,
        height: 32,
        child: const Text('Open menu'),
      ),
    );
  }
}

Future<void> _pumpPopover(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  await tester.pump();
}
