import 'package:app_ui/app_ui.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

/// Common desktop controls built from semantic tokens.
@widgetbook.UseCase(name: 'control gallery', type: IdeButton)
Widget controlGallery(BuildContext context) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    spacing: context.appSpacing.xs,
    children: <Widget>[
      IdeButton(
        label: 'Primary action',
        leadingIcon: Icons.play_arrow,
        onPressed: () {},
      ),
      IdeButton(
        label: 'Secondary action',
        variant: IdeButtonVariant.secondary,
        onPressed: () {},
      ),
      IdeChip(label: 'Selected filter', selected: true, onPressed: () {}),
      IdeSwitch(value: true, onChanged: (_) {}),
    ],
  ),
);

/// Controlled compact tabs, including a loading destination.
@widgetbook.UseCase(name: 'desktop tabs', type: IdeTabs)
Widget desktopTabs(BuildContext context) => Center(
  child: SizedBox(
    width: 360,
    child: IdeTabs<int>(
      value: 1,
      semanticLabel: 'Workspace views',
      items: const <IdeTabItem<int>>[
        IdeTabItem<int>(
          value: 1,
          label: 'Editor',
          leadingIcon: Icons.code,
        ),
        IdeTabItem<int>(
          value: 2,
          label: 'Preview',
          loading: true,
          loadingSemanticLabel: 'Preview loading',
        ),
      ],
      onChanged: (_) {},
    ),
  ),
);

/// Semantic status-card tones.
@widgetbook.UseCase(name: 'status tones', type: IdeStatusCard)
Widget statusTones(BuildContext context) => Center(
  child: SizedBox(
    width: 420,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final tone in IdeStatusCardTone.values)
          IdeStatusCard(
            tone: tone,
            title: tone.name,
            body: const Text('Caller-supplied status detail'),
          ),
      ],
    ),
  ),
);

/// Pure-UI Windows frame with injected logo and callbacks.
@widgetbook.UseCase(name: 'Windows shell', type: WindowFrame)
Widget windowsShell(BuildContext context) => Center(
  child: SizedBox(
    width: 720,
    height: 420,
    child: WindowFrame(
      showCustomTitleBar: true,
      platform: WindowFramePlatform.windows,
      windowsLogo: const Icon(Icons.flutter_dash, size: 22),
      windowsLogoSemanticLabel: 'Zeta logo',
      menuSemanticLabel: 'Application menu',
      menus: const <WindowMenu>[
        WindowMenu(
          label: 'File',
          items: <WindowMenuItem>[WindowMenuItem(label: 'Disabled item')],
        ),
      ],
      windowControls: WindowControlSet(
        minimizeLabel: 'Minimize',
        maximizeLabel: 'Maximize',
        restoreLabel: 'Restore',
        closeLabel: 'Close',
        onMinimize: () {},
        onToggleMaximize: () {},
        onClose: () {},
      ),
      child: const Center(child: Text('Workbench content')),
    ),
  ),
);

/// Responsive workbench composed entirely from shared UI primitives.
@widgetbook.UseCase(name: 'responsive workbench', type: IdeWorkbenchScaffold)
Widget responsiveWorkbench(BuildContext context) => Center(
  child: SizedBox(
    width: 1100,
    height: 640,
    child: IdeWorkbenchScaffold(
      closeOverlaySemanticLabel: 'Close side panel',
      leadingRailBuilder: (context, mode) => IdeActivityRail(
        leadingActions: <IdeRailAction>[
          IdeRailAction(
            icon: Icons.folder_outlined,
            tooltip: 'Projects',
            semanticLabel: 'Projects',
            active: true,
            onPressed: () {},
          ),
          IdeRailAction(
            icon: Icons.chat_bubble_outline,
            tooltip: 'Threads',
            semanticLabel: 'Threads',
            active: false,
            onPressed: () {},
          ),
        ],
      ),
      navigationPane: const IdeSurface.pane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IdePageHeader(title: 'Workspace'),
            IdeListRow(
              title: 'Migration plan',
              subtitle: 'Active now',
              selected: true,
              showDivider: false,
            ),
            IdeListRow(
              title: 'Architecture review',
              subtitle: 'Yesterday',
              showDivider: false,
            ),
          ],
        ),
      ),
      inspectorPane: const IdeSurface.pane(
        child: IdePageBody(
          child: IdeRowGroup(
            title: 'SESSION',
            dividers: false,
            children: <Widget>[
              IdeKeyValueRow(label: 'Model', value: 'gpt-5.6'),
              IdeKeyValueRow(
                label: 'Tokens',
                value: '42,810',
                tone: IdeKeyValueTone.numeric,
              ),
            ],
          ),
        ),
      ),
      canvas: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const IdePageHeader(
            title: 'Migration plan',
            subtitle: 'VGV architecture',
          ),
          IdeToolbar(
            child: Row(
              children: <Widget>[
                Text('Workbench', style: context.appTypography.toolbarLabel),
                const Spacer(),
                const IdeChip(label: 'Connected', selected: true),
              ],
            ),
          ),
          Expanded(
            child: IdePageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const CompactMetricBar(
                    items: <CompactMetricItem>[
                      CompactMetricItem(label: 'Steps', value: '27'),
                      CompactMetricItem(label: 'Passed', value: '26'),
                      CompactMetricItem(label: 'Coverage', value: '100%'),
                    ],
                  ),
                  SizedBox(height: context.appSpacing.md),
                  const IdeSection(
                    title: 'Current increment',
                    subtitle: 'Workbench primitives',
                    child: IdeStatusCard(
                      tone: IdeStatusCardTone.success,
                      title: 'Local gates are green',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

/// Dynamic-height list with shared metrics and caller-owned accessible copy.
@widgetbook.UseCase(name: 'dynamic conversation', type: IdeVirtualScrollShell)
Widget dynamicConversation(BuildContext context) => const Center(
  child: SizedBox(
    width: 560,
    height: 520,
    child: _VirtualizationPreview(),
  ),
);

final class _VirtualizationPreview extends StatefulWidget {
  const _VirtualizationPreview();

  @override
  State<_VirtualizationPreview> createState() => _VirtualizationPreviewState();
}

final class _VirtualizationPreviewState extends State<_VirtualizationPreview> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IdeVirtualScrollShell(
      controller: _controller,
      scrollbarSemanticLabel: 'Conversation scrollbar',
      scrollToEndSemanticLabel: 'Scroll to latest message',
      newContentLabel: 'New content',
      backToBottomLabel: 'Back to bottom',
      showScrollToEndButton: true,
      hasNewContent: true,
      onScrollToEnd: () {
        if (_controller.hasClients) {
          _controller.jumpTo(_controller.position.maxScrollExtent);
        }
      },
      child: ListView.builder(
        controller: _controller,
        itemCount: 200,
        padding: context.appSpacing.panelPadding,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(bottom: context.appSpacing.xs),
          child: IdeStatusCard(
            tone: index.isEven
                ? IdeStatusCardTone.neutral
                : IdeStatusCardTone.info,
            title: 'Virtual message ${index + 1}',
            body: Text(
              index % 3 == 0
                  ? 'A variable-height message with additional detail.'
                  : 'A compact message.',
            ),
          ),
        ),
      ),
    );
  }
}
