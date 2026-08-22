import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('does not render for an unsupported provider', (tester) async {
    await tester.pumpWidget(
      const _ThemeHarness(
        child: AgentModeSelector(status: AgentModeSelectorStatus.unavailable),
      ),
    );

    expect(find.byKey(const ValueKey('agent-mode-selector')), findsNothing);
  });

  testWidgets('renders disabled loading and error states', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const _ThemeHarness(
        child: AgentModeSelector(status: AgentModeSelectorStatus.loading),
      ),
    );

    expect(find.text('Mode…'), findsOneWidget);
    expect(
      tester
          .widget<PaneInteractiveSurface>(
            find.byKey(const ValueKey('agent-mode-selector')),
          )
          .enabled,
      isFalse,
    );

    await tester.pumpWidget(
      const _ThemeHarness(
        child: AgentModeSelector(
          status: AgentModeSelectorStatus.error,
          statusMessage: '目录加载失败',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Mode unavailable'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('agent-mode-selector')))
          .label,
      contains('Mode unavailable，对话模式，目录加载失败'),
    );
    expect(
      tester
          .widget<PaneInteractiveSurface>(
            find.byKey(const ValueKey('agent-mode-selector')),
          )
          .enabled,
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('shows Default and Plan preset labels and selects once', (
    tester,
  ) async {
    final selections = <AgentConversationModeId>[];
    await tester.pumpWidget(
      _ThemeHarness(child: _SelectorHarness(onChanged: selections.add)),
    );

    expect(find.text('Default'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-mode-selector')));
    await _pumpPopoverAnimation(tester);

    expect(
      find.byKey(const ValueKey('agent-mode-selector-popover')),
      findsOneWidget,
    );
    expect(
      find.byType(sf.SelectPopup<AgentConversationModeId>),
      findsOneWidget,
    );
    expect(find.text('Default'), findsWidgets);
    expect(find.text('Plan · medium'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-mode-option-plan')));
    await _pumpPopoverAnimation(tester);

    expect(selections, <AgentConversationModeId>[AgentConversationModeId.plan]);
    expect(find.text('Plan · medium'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-mode-selector')));
    await _pumpPopoverAnimation(tester);
    await tester.tap(find.byKey(const ValueKey('agent-mode-option-plan')));
    await _pumpPopoverAnimation(tester);

    expect(selections, hasLength(1));
  });

  testWidgets('keeps unavailable presets disabled in SelectPopup', (
    tester,
  ) async {
    final selections = <AgentConversationModeId>[];
    await tester.pumpWidget(
      _ThemeHarness(
        child: AgentModeSelector(
          status: AgentModeSelectorStatus.ready,
          presets: const <AgentConversationModePreset>[
            AgentConversationModePreset(
              id: AgentConversationModeId.defaultMode,
              displayName: 'Default',
            ),
            AgentConversationModePreset(
              id: AgentConversationModeId.plan,
              displayName: 'Plan',
              isSelectable: false,
            ),
          ],
          selectedMode: AgentConversationModeId.defaultMode,
          onChanged: selections.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('agent-mode-selector')));
    await _pumpPopoverAnimation(tester);
    final planOption = tester
        .widget<sf.SelectItemButton<AgentConversationModeId>>(
          find.byKey(const ValueKey('agent-mode-option-plan')),
        );
    expect(planOption.enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('agent-mode-option-plan')));
    await tester.pump();
    expect(selections, isEmpty);
    expect(
      find.byKey(const ValueKey('agent-mode-selector-popover')),
      findsOneWidget,
    );
  });

  testWidgets('shows next-turn and unknown mode semantics', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const _ThemeHarness(
        child: AgentModeSelector(
          status: AgentModeSelectorStatus.ready,
          presets: _modePresets,
          selectedMode: AgentConversationModeId.plan,
          appliesToNextTurn: true,
        ),
      ),
    );

    expect(find.text('Plan · medium · 下一回合'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('agent-mode-selector')))
          .label,
      contains('Plan · medium，对话模式，下一回合生效'),
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '对话模式图标',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _ThemeHarness(
        child: AgentModeSelector(
          status: AgentModeSelectorStatus.ready,
          presets: _modePresets,
          selectedMode: AgentConversationModeId.fromRaw('custom'),
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Custom mode'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('agent-mode-selector')))
          .label,
      contains('Custom mode，对话模式，当前模式只读'),
    );
    await tester.tap(find.byKey(const ValueKey('agent-mode-selector')));
    await _pumpPopoverAnimation(tester);
    expect(
      find.byKey(const ValueKey('agent-mode-unknown-notice')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('supports keyboard opening, navigation, selection and escape', (
    tester,
  ) async {
    final selections = <AgentConversationModeId>[];
    await tester.pumpWidget(
      _ThemeHarness(child: _SelectorHarness(onChanged: selections.add)),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'agent-mode-selector-trigger',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpPopoverAnimation(tester);
    expect(
      find.byKey(const ValueKey('agent-mode-selector-popover')),
      findsOneWidget,
    );

    // SelectPopup 内容层打开后由第一次方向键进入首项，再移动到 Plan。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpPopoverAnimation(tester);
    expect(selections, <AgentConversationModeId>[AgentConversationModeId.plan]);
    expect(find.text('Plan · medium'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'agent-mode-selector-trigger',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _pumpPopoverAnimation(tester);
    expect(
      find.byKey(const ValueKey('agent-mode-selector-popover')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpPopoverAnimation(tester);
    expect(
      find.byKey(const ValueKey('agent-mode-selector-popover')),
      findsNothing,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'agent-mode-selector-trigger',
    );
  });

  testWidgets('trigger toggle and outside tap close and refocus', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemeHarness(
        child: AgentModeSelector(
          status: AgentModeSelectorStatus.ready,
          presets: _modePresets,
          selectedMode: AgentConversationModeId.defaultMode,
          onChanged: _ignoreModeSelection,
        ),
      ),
    );
    final trigger = find.byKey(const ValueKey('agent-mode-selector'));
    final popover = find.byKey(const ValueKey('agent-mode-selector-popover'));

    await tester.tap(trigger);
    await _pumpPopoverAnimation(tester);
    expect(popover, findsOneWidget);
    await tester.tap(trigger);
    await _pumpPopoverAnimation(tester);
    expect(popover, findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'agent-mode-selector-trigger',
    );

    await tester.tap(trigger);
    await _pumpPopoverAnimation(tester);
    expect(popover, findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await _pumpPopoverAnimation(tester);
    expect(popover, findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'agent-mode-selector-trigger',
    );
  });

  testWidgets('opens above near the bottom with zero-duration reduced motion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 260);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const _ThemeHarness(
        alignment: Alignment.bottomCenter,
        disableAnimations: true,
        child: Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: AgentModeSelector(
            status: AgentModeSelectorStatus.ready,
            presets: _modePresets,
            selectedMode: AgentConversationModeId.defaultMode,
            onChanged: _ignoreModeSelection,
          ),
        ),
      ),
    );
    final trigger = find.byKey(const ValueKey('agent-mode-selector'));
    final popover = find.byKey(const ValueKey('agent-mode-selector-popover'));

    await tester.tap(trigger);
    await tester.pump();
    await tester.pump();
    expect(popover, findsOneWidget);
    expect(
      tester.getRect(popover).bottom,
      lessThanOrEqualTo(tester.getRect(trigger).top),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(popover, findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'agent-mode-selector-trigger',
    );
  });

  testWidgets('closes stale popover when conversation context changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _ThemeHarness(
        child: AgentModeSelector(
          status: AgentModeSelectorStatus.ready,
          presets: _modePresets,
          selectedMode: AgentConversationModeId.defaultMode,
          contextId: 'thread-a',
          onChanged: _ignoreModeSelection,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('agent-mode-selector')));
    await _pumpPopoverAnimation(tester);
    expect(
      find.byKey(const ValueKey('agent-mode-selector-popover')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      const _ThemeHarness(
        child: AgentModeSelector(
          status: AgentModeSelectorStatus.ready,
          presets: _modePresets,
          selectedMode: AgentConversationModeId.defaultMode,
          contextId: 'thread-b',
          onChanged: _ignoreModeSelection,
        ),
      ),
    );
    await _pumpPopoverAnimation(tester);

    expect(
      find.byKey(const ValueKey('agent-mode-selector-popover')),
      findsNothing,
    );
  });

  testWidgets('keeps labels bounded in a narrow large-text viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(180, 280);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const _ThemeHarness(
        textScaler: TextScaler.linear(2),
        child: SizedBox(
          width: 136,
          child: AgentModeSelector(
            status: AgentModeSelectorStatus.ready,
            presets: _modePresets,
            selectedMode: AgentConversationModeId.plan,
            appliesToNextTurn: true,
            onChanged: _ignoreModeSelection,
          ),
        ),
      ),
    );

    expect(find.text('Plan · medium · 下一回合'), findsOneWidget);
    final triggerLabel = tester.widget<Text>(
      find.byKey(const ValueKey('agent-mode-selector-label')),
    );
    expect(triggerLabel.maxLines, 1);
    expect(triggerLabel.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('agent-mode-selector')));
    await _pumpPopoverAnimation(tester);
    expect(find.text('Plan · medium'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

void _ignoreModeSelection(AgentConversationModeId _) {}

Future<void> _pumpPopoverAnimation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

const _modePresets = <AgentConversationModePreset>[
  AgentConversationModePreset(
    id: AgentConversationModeId.defaultMode,
    displayName: 'Default',
  ),
  AgentConversationModePreset(
    id: AgentConversationModeId.plan,
    displayName: 'Plan',
    suggestedReasoningEffort: 'medium',
  ),
];

class _SelectorHarness extends StatefulWidget {
  const _SelectorHarness({required this.onChanged});

  final ValueChanged<AgentConversationModeId> onChanged;

  @override
  State<_SelectorHarness> createState() => _SelectorHarnessState();
}

class _SelectorHarnessState extends State<_SelectorHarness> {
  AgentConversationModeId _selectedMode = AgentConversationModeId.defaultMode;

  @override
  Widget build(BuildContext context) {
    return AgentModeSelector(
      status: AgentModeSelectorStatus.ready,
      presets: _modePresets,
      selectedMode: _selectedMode,
      onChanged: (mode) {
        widget.onChanged(mode);
        if (mode != _selectedMode) {
          setState(() {
            _selectedMode = mode;
          });
        }
      },
    );
  }
}

class _ThemeHarness extends StatelessWidget {
  const _ThemeHarness({
    required this.child,
    this.textScaler = TextScaler.noScaling,
    this.alignment = Alignment.center,
    this.disableAnimations = false,
  });

  final Widget child;
  final TextScaler textScaler;
  final AlignmentGeometry alignment;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final lightIdeTheme = buildIdeThemeData(
      brightness: Brightness.light,
      codeFontFamily: 'CodeFont',
    );
    final darkIdeTheme = buildIdeThemeData(
      brightness: Brightness.dark,
      codeFontFamily: 'CodeFont',
    );
    return IdeThemeScope(
      themeMode: ThemeMode.light,
      lightTheme: lightIdeTheme,
      darkTheme: darkIdeTheme,
      child: sf.ShadcnApp(
        locale: ZetaLocalization.simplifiedChinese,
        supportedLocales: ZetaLocalization.supportedLocales,
        localizationsDelegates: ZetaLocalization.delegates,
        theme: buildShadcnTheme(lightIdeTheme),
        darkTheme: buildShadcnTheme(darkIdeTheme),
        materialTheme: buildMaterialTheme(lightIdeTheme),
        themeMode: sf.ThemeMode.light,
        home: Builder(
          builder: (context) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: textScaler,
                disableAnimations: disableAnimations,
              ),
              child: sf.Scaffold(
                child: Align(alignment: alignment, child: child),
              ),
            );
          },
        ),
      ),
    );
  }
}
