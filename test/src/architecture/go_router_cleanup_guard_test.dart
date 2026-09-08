import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// W7：路由直渲后不得把显示选中态或保活栈接回去。
void main() {
  test('IdeRetainedPageView 文件不得复活', () {
    expect(
      File(
        'packages/zeta_ui/lib/src/workbench/ide_retained_page_view.dart',
      ).existsSync(),
      isFalse,
    );
    expect(
      File('test/src/ui/core/ide_retained_page_view_test.dart').existsSync(),
      isFalse,
    );
  });

  test('侧栏会话高亮不得回退 slice selectedThreadId', () {
    final source = File(
      'lib/src/ui/features/ide/views/project_list_pane.dart',
    ).readAsStringSync();
    expect(source.contains('state.selectedThreadId'), isFalse);
  });

  test('项目行高亮不得回退 workspace.activeProjectPath', () {
    final source = File(
      'lib/src/ui/features/ide/views/ide_home.dart',
    ).readAsStringSync();
    expect(
      source.contains('routeProjectPath ?? workspace.activeProjectPath'),
      isFalse,
    );
  });

  test('AgentPane 不再保留 keep-alive isActive', () {
    final pane = File(
      'lib/src/features/agent/presentation/agent_pane.dart',
    ).readAsStringSync();
    expect(pane.contains('final bool isActive'), isFalse);
    expect(pane.contains('this.isActive'), isFalse);
  });
}
