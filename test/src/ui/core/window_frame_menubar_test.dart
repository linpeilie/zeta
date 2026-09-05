import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta_ui/zeta_ui.dart';
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
      expect(find.byKey(const ValueKey('window-menu-trigger')), findsOneWidget);
      // 顶层菜单折叠为单个汉堡 icon，不再展示各菜单组的文字标签。
      expect(find.text('文件'), findsNothing);
      expect(find.byIcon(sf.LucideIcons.menu), findsOneWidget);

      // 触发按钮不再靠标题栏高度撑开，而是按 padding + icon 自然定形，
      // 与其它标题栏 icon 按钮（IdeMetrics.iconButtonHitSize）看齐成正方形，
      // 由 _TitleBar 外层 Row 居中，而不是撑到 shadcn menubar 默认的
      // 文字按钮尺寸（约 40px 宽、标题栏整高）。
      final menuButton = find.byKey(const ValueKey('window-menu-trigger'));
      final menuIcon = find.byIcon(sf.LucideIcons.menu);
      final titleBarSize = tester.getSize(
        find.byKey(const ValueKey('window-title-bar')),
      );
      expect(
        tester.getSize(menuButton),
        const Size(IdeMetrics.iconButtonHitSize, IdeMetrics.iconButtonHitSize),
      );
      expect(
        tester.getCenter(menuIcon).dy,
        closeTo(tester.getCenter(menuButton).dy, 0.01),
      );
      expect(
        titleBarSize.height,
        greaterThanOrEqualTo(IdeMetrics.titleBarHeight),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      final menuButtonCenter = tester.getCenter(menuButton);
      await mouse.moveTo(menuButtonCenter);
      await tester.pump();
      await mouse.down(menuButtonCenter);
      await mouse.up();
      // Menubar / popover 可能持有持续动画，避免 pumpAndSettle。
      await tester.pump();
      // 在展开动画内移动真实桌面鼠标，回归 Overlay 命中测试与 MouseTracker
      // 设备更新交叠的生产故障路径。
      await mouse.moveTo(tester.getCenter(find.text('打开项目')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('打开项目'), findsOneWidget);
      expect(find.text('退出'), findsOneWidget);

      final menuItem = find.byKey(const ValueKey('window-menu-open-project'));
      final menuItemCenter = tester.getCenter(menuItem);
      await mouse.down(menuItemCenter);
      await mouse.up();
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
          brandLogo: _brandLogo,
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
      final menuFinder = find.byKey(const ValueKey('window-menu-trigger'));
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
      // 尺寸盒由设计系统提供；图形本身是宿主注入的，zeta_ui 不认识它。
      final logoBox = tester.widget<SizedBox>(
        find.descendant(of: logoFinder, matching: find.byType(SizedBox)).first,
      );
      expect(logoBox.width, 22);
      expect(logoBox.height, 22);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('标题栏与工作台之间不画底部分隔线', (tester) async {
    await _withTargetPlatform(TargetPlatform.windows, () async {
      await pumpIdeComponent(
        tester,
        size: const Size(960, 640),
        child: const WindowFrame(
          enableNativeWindowFrame: true,
          showWindowControls: false,
          child: ColoredBox(color: Colors.black),
        ),
      );

      final titleBar = find.byKey(const ValueKey('window-title-bar'));
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(
                          of: titleBar,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.border, isNull);
      expect(decoration.color, IdeColors.of(tester.element(titleBar)).frame);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('macOS 标题栏同样展示菜单图标', (tester) async {
    await _withTargetPlatform(TargetPlatform.macOS, () async {
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
              items: <WindowMenuItem>[WindowMenuItem(label: '打开项目')],
            ),
          ],
          child: const ColoredBox(color: Colors.black),
        ),
      );

      expect(find.byKey(const ValueKey('window-menu-trigger')), findsOneWidget);
      expect(find.byIcon(sf.LucideIcons.menu), findsOneWidget);
      expect(find.byIcon(sf.LucideIcons.minus), findsNothing);
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
            brandLogo: _brandLogo,
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
        final menu = find.byKey(const ValueKey('window-menu-trigger'));
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
          brandLogo: _brandLogo,
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
      final menu = find.byKey(const ValueKey('window-menu-trigger'));

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
          brandLogo: _brandLogo,
          menus: menus,
          child: ColoredBox(color: Colors.black),
        ),
      );
      final originalLogoRect = tester.getRect(
        find.byKey(const ValueKey('window-title-bar-logo')),
      );
      final originalMenuRect = tester.getRect(
        find.byKey(const ValueKey('window-menu-trigger')),
      );
      final originalDragRect = tester.getRect(find.byType(DragToMoveArea));

      await pumpIdeComponent(
        tester,
        size: const Size(960, 640),
        child: const WindowFrame(
          enableNativeWindowFrame: true,
          showWindowControls: false,
          brandLogo: _brandLogo,
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
        tester.getRect(find.byKey(const ValueKey('window-menu-trigger'))),
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
          brandLogo: _brandLogo,
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

/// 宿主注入的品牌图形占位。
///
/// `zeta_ui` 不拥有品牌资产（`assets/branding/*` 由根 app 声明），
/// 因此测试里用一个不依赖资产的占位 Widget 代替真实 Logo。
const Widget _brandLogo = SizedBox.square(
  dimension: 22,
  key: ValueKey('test-brand-logo'),
);
