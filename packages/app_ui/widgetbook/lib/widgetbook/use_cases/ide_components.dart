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
