import 'package:app_ui/app_ui.dart';

/// Lays out the active page while retaining state for previously visited pages.
class IdeRetainedPageView extends StatefulWidget {
  /// Creates a retained page view.
  const IdeRetainedPageView({
    required this.pages,
    required this.selectedId,
    super.key,
  });

  /// Pages with unique stable identities.
  final List<IdeRetainedPage> pages;

  /// Identity of the active page. Unknown values select the first page.
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
    if (pages.isEmpty) return const SizedBox.expand();

    return PageView.builder(
      key: const ValueKey<String>('ide-retained-page-view'),
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pages.length,
      findChildIndexCallback: (key) {
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
          active: index == _currentIndex,
          child: page.child,
        );
      },
    );
  }

  int _resolveIndex(String selectedId, List<IdeRetainedPage> pages) {
    if (pages.isEmpty) return 0;
    final index = pages.indexWhere((page) => page.id == selectedId);
    return index < 0 ? 0 : index;
  }

  bool _samePageIds(List<IdeRetainedPage> a, List<IdeRetainedPage> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].id != b[index].id) return false;
    }
    return true;
  }

  void _scheduleJumpTo(int index) {
    void jump() {
      if (!mounted || !_controller.hasClients) return;
      final current = _controller.page?.round();
      if (current != index) _controller.jumpToPage(index);
    }

    if (_controller.hasClients) {
      jump();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => jump());
  }
}

class _IdeRetainedKeepAlivePage extends StatefulWidget {
  const _IdeRetainedKeepAlivePage({
    required this.active,
    required this.child,
    super.key,
  });

  final bool active;
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
    return TickerMode(
      enabled: widget.active,
      child: SizedBox.expand(child: widget.child),
    );
  }
}
