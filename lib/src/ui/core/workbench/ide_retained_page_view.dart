import 'package:flutter/material.dart';

/// 惰性保留页面描述：稳定 [id] + 页面内容。
///
/// [id] 必须在同一 [IdeRetainedPageView] 内唯一，并用于 Element 匹配与
/// `findChildIndexCallback`，避免列表增删后 State 串位。
class IdeRetainedPage {
  const IdeRetainedPage({required this.id, required this.child});

  /// 稳定页面身份（entryId / page name 等）。
  final String id;

  /// 页面内容。未访问过的页面在 [PageView.builder] 中不会立刻构建。
  final Widget child;
}

/// 只布局当前活动页、同时 keep-alive 已访问页的保留式页面容器。
///
/// 用于替代会布局全部 child 的 [IndexedStack]：
/// - 不可手势滚动，索引由 [selectedId] 驱动并以 [PageController.jumpToPage] 同步；
/// - 已访问页通过 [AutomaticKeepAliveClientMixin] 保留 State（草稿、滚动等）；
/// - 离屏 keep-alive 子树不参与父约束的持续 layout。
class IdeRetainedPageView extends StatefulWidget {
  const IdeRetainedPageView({
    required this.pages,
    required this.selectedId,
    super.key,
  });

  final List<IdeRetainedPage> pages;
  final String selectedId;

  @override
  State<IdeRetainedPageView> createState() => _IdeRetainedPageViewState();
}

class _IdeRetainedPageViewState extends State<IdeRetainedPageView> {
  late PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = _resolveIndex(widget.selectedId, widget.pages);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void didUpdateWidget(covariant IdeRetainedPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = _resolveIndex(widget.selectedId, widget.pages);
    if (nextIndex != _currentIndex) {
      _currentIndex = nextIndex;
      _scheduleJumpTo(_currentIndex);
      return;
    }
    // 列表结构变化但选中 id 不变时，仍校正到合法 index。
    if (!_samePageIds(oldWidget.pages, widget.pages)) {
      _scheduleJumpTo(_currentIndex);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.pages;
    if (pages.isEmpty) {
      return const SizedBox.expand();
    }

    final safeIndex = _currentIndex.clamp(0, pages.length - 1);
    if (safeIndex != _currentIndex) {
      _currentIndex = safeIndex;
      _scheduleJumpTo(safeIndex);
    }

    return PageView.builder(
      key: const ValueKey('ide-retained-page-view'),
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(),
      allowImplicitScrolling: false,
      itemCount: pages.length,
      findChildIndexCallback: (Key key) {
        if (key is ValueKey<String>) {
          final index = pages.indexWhere((page) => page.id == key.value);
          return index >= 0 ? index : null;
        }
        return null;
      },
      itemBuilder: (context, index) {
        final page = pages[index];
        return _IdeRetainedKeepAlivePage(
          key: ValueKey<String>(page.id),
          child: page.child,
        );
      },
    );
  }

  int _resolveIndex(String selectedId, List<IdeRetainedPage> pages) {
    if (pages.isEmpty) {
      return 0;
    }
    final index = pages.indexWhere((page) => page.id == selectedId);
    if (index < 0) {
      return 0;
    }
    return index;
  }

  bool _samePageIds(List<IdeRetainedPage> a, List<IdeRetainedPage> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i].id != b[i].id) {
        return false;
      }
    }
    return true;
  }

  void _scheduleJumpTo(int index) {
    void jump() {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final current = _controller.page?.round();
      if (current != index) {
        _controller.jumpToPage(index);
      }
    }

    if (_controller.hasClients) {
      jump();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => jump());
  }
}

class _IdeRetainedKeepAlivePage extends StatefulWidget {
  const _IdeRetainedKeepAlivePage({required this.child, super.key});

  final Widget child;

  @override
  State<_IdeRetainedKeepAlivePage> createState() =>
      _IdeRetainedKeepAlivePageState();
}

class _IdeRetainedKeepAlivePageState extends State<_IdeRetainedKeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // PageView 子项默认不强制撑满；expand 保证 Agent/Settings 获得有界约束。
    return SizedBox.expand(child: widget.child);
  }
}
