import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/ui/core/ide_activity_rail.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/rows/ide_list_row.dart';
import 'package:zeta/src/ui/core/workbench/ide_page_header.dart';
import 'package:zeta/src/ui/core/workbench/ide_workbench_scaffold.dart';

import 'ide_component_test_harness.dart';

void main() {
  for (final themeMode in <ThemeMode>[ThemeMode.dark, ThemeMode.light]) {
    final themeName = themeMode.name;

    testWidgets('Workbench $themeName wide golden', (tester) async {
      await _expectWorkbenchGolden(
        tester,
        themeMode: themeMode,
        size: const Size(1440, 900),
        fileName: 'workbench_${themeName}_wide.png',
      );
    });

    testWidgets('Workbench $themeName medium golden', (tester) async {
      await _expectWorkbenchGolden(
        tester,
        themeMode: themeMode,
        size: const Size(1000, 700),
        activeOverlay: IdeWorkbenchOverlay.inspector,
        fileName: 'workbench_${themeName}_medium.png',
      );
    });

    testWidgets('Workbench $themeName compact golden', (tester) async {
      await _expectWorkbenchGolden(
        tester,
        themeMode: themeMode,
        size: const Size(800, 700),
        activeOverlay: IdeWorkbenchOverlay.navigation,
        fileName: 'workbench_${themeName}_compact.png',
      );
    });
  }
}

Future<void> _expectWorkbenchGolden(
  WidgetTester tester, {
  required ThemeMode themeMode,
  required Size size,
  required String fileName,
  IdeWorkbenchOverlay? activeOverlay,
}) async {
  await pumpIdeComponent(
    tester,
    themeMode: themeMode,
    size: size,
    child: RepaintBoundary(
      key: const ValueKey('workbench-golden-boundary'),
      child: _WorkbenchGoldenScene(activeOverlay: activeOverlay),
    ),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byKey(const ValueKey('workbench-golden-boundary')),
    matchesGoldenFile('../../../goldens/$fileName'),
  );
}

class _WorkbenchGoldenScene extends StatelessWidget {
  const _WorkbenchGoldenScene({this.activeOverlay});

  final IdeWorkbenchOverlay? activeOverlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(IdeSpacing.space8),
      child: IdeWorkbenchScaffold(
        leadingRailBuilder: (context, mode) => IdeActivityRail(
          indicatorSide: IdeActivityRailIndicatorSide.right,
          leadingActions: [
            IdeRailAction(
              icon: Icons.account_tree_rounded,
              tooltip: 'Projects',
              semanticLabel: 'Projects',
              active: true,
              onPressed: () {},
            ),
          ],
        ),
        navigationPane: const _GoldenNavigationPane(),
        canvas: const _GoldenCanvas(),
        inspectorPane: const _GoldenInspectorPane(),
        trailingRailBuilder: (context, mode) => IdeActivityRail(
          leadingActions: [
            IdeRailAction(
              icon: Icons.folder_rounded,
              tooltip: 'Files',
              semanticLabel: 'Files',
              active: activeOverlay == IdeWorkbenchOverlay.inspector,
              onPressed: () {},
            ),
          ],
        ),
        activeOverlay: activeOverlay,
        onDismissOverlay: activeOverlay == null ? null : () {},
      ),
    );
  }
}

class _GoldenNavigationPane extends StatelessWidget {
  const _GoldenNavigationPane();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdePageHeader(title: 'Projects', subtitle: 'Recent workspaces'),
        IdeListRow(
          title: 'zeta',
          subtitle: 'D:/Development/Workspace/zeta',
          leading: Icon(Icons.folder_open_rounded),
          selected: true,
        ),
        IdeListRow(
          title: 'design-system',
          subtitle: 'Updated yesterday',
          leading: Icon(Icons.folder_outlined),
        ),
      ],
    );
  }
}

class _GoldenCanvas extends StatelessWidget {
  const _GoldenCanvas();

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const IdePageHeader(
          title: 'Agent',
          subtitle: 'Responsive workbench preview',
        ),
        Expanded(
          child: Padding(
            padding: IdeSpacing.all16,
            child: Align(
              alignment: Alignment.topRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.userMessageSurface,
                    borderRadius: IdeRadius.allMedium,
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: const Padding(
                    padding: IdeSpacing.inputContentPadding,
                    child: Text(
                      'Please review the shared workbench surfaces and responsive behavior.',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GoldenInspectorPane extends StatelessWidget {
  const _GoldenInspectorPane();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdePageHeader(title: 'Context', subtitle: 'Selected files'),
        IdeListRow(
          title: 'ide_workbench_scaffold.dart',
          subtitle: 'Modified',
          leading: Icon(Icons.code_rounded),
        ),
      ],
    );
  }
}
