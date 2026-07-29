import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/window_frame.dart';

import 'ide_component_test_harness.dart';

void main() {
  testWidgets('WindowFrame 使用 shadcn Menubar 渲染标题栏菜单并可激活项', (tester) async {
    var openProjectPressed = 0;

    await pumpIdeComponent(
      tester,
      size: const Size(960, 640),
      child: WindowFrame(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        menus: [
          WindowMenu(
            key: const ValueKey('window-menu-file'),
            label: '文件',
            items: [
              WindowMenuItem(
                key: const ValueKey('window-menu-open-project'),
                label: '打开项目',
                onPressed: () => openProjectPressed += 1,
              ),
              const WindowMenuItem(
                key: ValueKey('window-menu-exit'),
                label: '退出',
              ),
            ],
          ),
        ],
        child: const ColoredBox(color: Colors.black),
      ),
    );

    expect(find.byType(sf.Menubar), findsOneWidget);
    expect(find.byKey(const ValueKey('window-menu-file')), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);

    // 标题栏最小高度走 IdeMetrics，Menubar 使用自然高度且不被 28px 裁切。
    final menubarSize = tester.getSize(find.byType(sf.Menubar));
    final titleBarSize = tester.getSize(
      find.byKey(const ValueKey('window-title-bar')),
    );
    expect(menubarSize.height, greaterThan(0));
    expect(
      titleBarSize.height,
      greaterThanOrEqualTo(IdeMetrics.titleBarHeight),
    );
    expect(titleBarSize.height, greaterThanOrEqualTo(menubarSize.height));

    await tester.tap(find.byKey(const ValueKey('window-menu-file')));
    // Menubar / popover 可能持有持续动画，避免 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('打开项目'), findsOneWidget);
    expect(find.text('退出'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('window-menu-open-project')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(openProjectPressed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows 标题栏左侧显示 Logo 并隐藏应用标题', (tester) async {
    await pumpIdeComponent(
      tester,
      size: const Size(960, 640),
      child: WindowFrame(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        menus: const [
          WindowMenu(
            key: ValueKey('window-menu-file'),
            label: '文件',
            items: <WindowMenuItem>[],
          ),
        ],
        child: const ColoredBox(color: Colors.black),
      ),
    );

    final logoFinder = find.byKey(const ValueKey('window-title-bar-logo'));
    final menuFinder = find.byKey(const ValueKey('window-menu-file'));
    expect(logoFinder, findsOneWidget);
    expect(find.text(appTitle), findsNothing);
    expect(
      tester.getTopLeft(logoFinder).dx,
      lessThan(tester.getTopLeft(menuFinder).dx),
    );
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
