import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/window_frame.dart';
import 'package:window_manager/window_manager.dart';

import 'ide_component_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowManagerChannel = MethodChannel('window_manager');
  late List<MethodCall> windowManagerCalls;

  setUp(() {
    windowManagerCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (call) async {
          windowManagerCalls.add(call);
          return switch (call.method) {
            'isFullScreen' || 'isMaximized' => false,
            _ => null,
          };
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
  });

  testWidgets('WindowFrame 使用 shadcn Menubar 渲染标题栏菜单并可激活项', (tester) async {
    await _withTargetPlatform(TargetPlatform.windows, () async {
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

      // Menubar 撑满标题栏的设计高度，顶层按钮与文字在该高度内垂直居中。
      final menuButton = find.byKey(const ValueKey('window-menu-file'));
      final menuLabel = find.text('文件');
      final menubarSize = tester.getSize(find.byType(sf.Menubar));
      final titleBarSize = tester.getSize(
        find.byKey(const ValueKey('window-title-bar')),
      );
      expect(menubarSize.height, IdeMetrics.titleBarHeight);
      expect(tester.getSize(menuButton).height, IdeMetrics.titleBarHeight);
      expect(
        tester.getCenter(menuLabel).dy,
        closeTo(tester.getCenter(menuButton).dy, 0.01),
      );
      expect(
        titleBarSize.height,
        greaterThanOrEqualTo(IdeMetrics.titleBarHeight),
      );

      await tester.tap(menuButton);
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
  });

  testWidgets('Windows 标题栏左侧显示 Logo 并隐藏应用标题', (tester) async {
    await _withTargetPlatform(TargetPlatform.windows, () async {
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

      // 契约：左 space8、右 space4，图标 22×22。
      final logoPadding = tester.widget<Padding>(
        find.descendant(of: logoFinder, matching: find.byType(Padding)).first,
      );
      expect(
        logoPadding.padding,
        const EdgeInsets.only(
          left: IdeSpacing.space8,
          right: IdeSpacing.space4,
        ),
      );
      final logoSvg = tester.widget<SvgPicture>(
        find.descendant(of: logoFinder, matching: find.byType(SvgPicture)),
      );
      expect(logoSvg.width, 22);
      expect(logoSvg.height, 22);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('macOS 标题栏拖拽区覆盖可见标题栏高度', (tester) async {
    await _withTargetPlatform(TargetPlatform.macOS, () async {
      await pumpIdeComponent(
        tester,
        size: const Size(960, 640),
        child: WindowFrame(
          enableNativeWindowFrame: true,
          showWindowControls: false,
          child: const ColoredBox(color: Colors.black),
        ),
      );

      final dragArea = find.byType(DragToMoveArea);
      expect(dragArea, findsOneWidget);
      expect(
        tester.getSize(dragArea).height,
        IdeMetrics.titleBarHeight - IdeSpacing.space4,
      );
      expect(tester.takeException(), isNull);
    });
  });

  for (final platform in <TargetPlatform>[
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('${platform.name} 标题栏左侧 action 位于平台保留区与菜单之间', (tester) async {
      await _withTargetPlatform(platform, () async {
        await pumpIdeComponent(
          tester,
          size: const Size(960, 640),
          child: WindowFrame(
            enableNativeWindowFrame: true,
            showWindowControls: false,
            titleBarLeadingActions: [
              WindowTitleBarAction(
                key: const ValueKey('window-leading-action'),
                icon: Icons.view_sidebar_outlined,
                tooltip: '显示左侧栏',
                semanticLabel: '显示左侧栏',
                onPressed: () {},
              ),
            ],
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

        final titleBar = find.byKey(const ValueKey('window-title-bar'));
        final action = find.byKey(const ValueKey('window-leading-action'));
        final menu = find.byKey(const ValueKey('window-menu-file'));
        final relativeActionLeft =
            tester.getTopLeft(action).dx - tester.getTopLeft(titleBar).dx;
        final expectedActionLeft = platform == TargetPlatform.macOS
            ? IdeMetrics.macOSTrafficLightGutter + IdeSpacing.space4
            : IdeSpacing.space4;

        expect(relativeActionLeft, closeTo(expectedActionLeft, 0.01));
        expect(
          tester.getTopRight(action).dx,
          lessThan(tester.getTopLeft(menu).dx),
        );
        expect(
          find.byKey(const ValueKey('window-title-bar-logo')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('Windows 标题栏最左侧展示 Logo，折叠 action 紧随其后', (tester) async {
    await _withTargetPlatform(TargetPlatform.windows, () async {
      await pumpIdeComponent(
        tester,
        size: const Size(960, 640),
        child: WindowFrame(
          enableNativeWindowFrame: true,
          showWindowControls: false,
          titleBarLeadingActions: [
            WindowTitleBarAction(
              key: const ValueKey('window-leading-action'),
              icon: Icons.view_sidebar_outlined,
              tooltip: '显示左侧栏',
              semanticLabel: '显示左侧栏',
              onPressed: () {},
            ),
          ],
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

      final titleBar = find.byKey(const ValueKey('window-title-bar'));
      final logo = find.byKey(const ValueKey('window-title-bar-logo'));
      final action = find.byKey(const ValueKey('window-leading-action'));
      final menu = find.byKey(const ValueKey('window-menu-file'));

      expect(logo, findsOneWidget);
      // 契约：Logo 紧贴标题栏最左边缘（其左外边距在 Logo 自身盒子内），
      // 折叠 action 紧随其后，menu 再之后。
      expect(
        tester.getTopLeft(logo).dx - tester.getTopLeft(titleBar).dx,
        closeTo(0, 0.01),
      );
      expect(
        tester.getTopRight(logo).dx,
        lessThan(tester.getTopLeft(action).dx),
      );
      expect(
        tester.getTopRight(action).dx,
        lessThan(tester.getTopLeft(menu).dx),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('省略左侧 actions 与显式空列表保持旧标题栏布局', (tester) async {
    await _withTargetPlatform(TargetPlatform.windows, () async {
      const menus = <WindowMenu>[
        WindowMenu(
          key: ValueKey('window-menu-file'),
          label: '文件',
          items: <WindowMenuItem>[],
        ),
      ];

      await pumpIdeComponent(
        tester,
        size: const Size(960, 640),
        child: const WindowFrame(
          enableNativeWindowFrame: true,
          showWindowControls: false,
          menus: menus,
          child: ColoredBox(color: Colors.black),
        ),
      );
      final originalLogoRect = tester.getRect(
        find.byKey(const ValueKey('window-title-bar-logo')),
      );
      final originalMenuRect = tester.getRect(
        find.byKey(const ValueKey('window-menu-file')),
      );
      final originalDragRect = tester.getRect(find.byType(DragToMoveArea));

      await pumpIdeComponent(
        tester,
        size: const Size(960, 640),
        child: const WindowFrame(
          enableNativeWindowFrame: true,
          showWindowControls: false,
          menus: menus,
          titleBarLeadingActions: <WindowTitleBarAction>[],
          child: ColoredBox(color: Colors.black),
        ),
      );

      expect(
        tester.getRect(find.byKey(const ValueKey('window-title-bar-logo'))),
        originalLogoRect,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('window-menu-file'))),
        originalMenuRect,
      );
      expect(tester.getRect(find.byType(DragToMoveArea)), originalDragRect);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('左侧 action 保留 tooltip、语义标签并可恢复焦点', (tester) async {
    await _withTargetPlatform(TargetPlatform.windows, () async {
      final actionFocusNode = FocusNode(debugLabel: 'window-leading-action');
      addTearDown(actionFocusNode.dispose);
      var pressed = 0;

      await pumpIdeComponent(
        tester,
        size: const Size(960, 640),
        child: WindowFrame(
          enableNativeWindowFrame: true,
          showWindowControls: false,
          titleBarLeadingActions: [
            WindowTitleBarAction(
              key: const ValueKey('window-leading-action'),
              icon: Icons.view_sidebar_outlined,
              tooltip: '显示左侧栏',
              semanticLabel: '显示左侧栏',
              focusNode: actionFocusNode,
              onPressed: () => pressed += 1,
            ),
          ],
          child: const ColoredBox(color: Colors.black),
        ),
      );

      final action = find.byKey(const ValueKey('window-leading-action'));
      expect(find.bySemanticsLabel('显示左侧栏'), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(action));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.text('显示左侧栏'), findsOneWidget);

      actionFocusNode.requestFocus();
      await tester.pump();
      expect(actionFocusNode.hasFocus, isTrue);
      actionFocusNode.unfocus();
      await tester.pump();
      expect(actionFocusNode.hasFocus, isFalse);
      actionFocusNode.requestFocus();
      await tester.pump();
      expect(actionFocusNode.hasFocus, isTrue);

      await tester.tap(action);
      await tester.pump();
      expect(pressed, 1);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('左侧 action 不影响拖拽区和 Windows 窗口按钮', (tester) async {
    await _withTargetPlatform(TargetPlatform.windows, () async {
      await pumpIdeComponent(
        tester,
        size: const Size(960, 640),
        child: WindowFrame(
          enableNativeWindowFrame: true,
          titleBarLeadingActions: [
            WindowTitleBarAction(
              key: const ValueKey('window-leading-action'),
              icon: Icons.view_sidebar_outlined,
              tooltip: '显示左侧栏',
              semanticLabel: '显示左侧栏',
              onPressed: () {},
            ),
          ],
          child: const ColoredBox(color: Colors.black),
        ),
      );
      await tester.pump();

      final dragArea = find.byType(DragToMoveArea);
      expect(dragArea, findsOneWidget);
      expect(tester.getSize(dragArea).width, greaterThan(0));
      expect(find.byIcon(sf.LucideIcons.minus), findsOneWidget);
      expect(find.byIcon(sf.LucideIcons.maximize), findsOneWidget);
      expect(find.byIcon(sf.LucideIcons.x), findsOneWidget);

      await tester.drag(dragArea, const Offset(24, 0));
      await tester.pump();
      await tester.tap(find.byIcon(sf.LucideIcons.minus));
      await tester.tap(find.byIcon(sf.LucideIcons.maximize));
      await tester.tap(find.byIcon(sf.LucideIcons.x));
      await tester.pump();
      // DragToMoveArea 同时注册双击手势，推进识别器的短暂等待窗口。
      await tester.pump(const Duration(milliseconds: 50));

      final calledMethods = windowManagerCalls
          .map((call) => call.method)
          .toList(growable: false);
      expect(calledMethods, contains('startDragging'));
      expect(
        calledMethods,
        containsAll(<String>['minimize', 'maximize', 'close']),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _withTargetPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
