part of '../agent_pane.dart';

const double _agentMentionFilePickerPreferredWidth = 360;
const double _agentMentionFilePickerPreferredMaxHeight = 280;

/// @-mention 文件候选的高亮与候选状态，供 Composer 键盘与 popover 共享。
final class _MentionFileListController extends ChangeNotifier {
  List<WorkspaceNode> _candidates = const <WorkspaceNode>[];
  int _highlightIndex = 0;

  List<WorkspaceNode> get candidates => _candidates;

  int get highlightIndex => _highlightIndex;

  WorkspaceNode? get highlighted {
    if (_candidates.isEmpty) {
      return null;
    }
    return _candidates[_highlightIndex.clamp(0, _candidates.length - 1)];
  }

  void syncCandidates(List<WorkspaceNode> next) {
    final previousPath = highlighted?.path;
    _candidates = List<WorkspaceNode>.unmodifiable(next);
    if (_candidates.isEmpty) {
      _highlightIndex = 0;
      notifyListeners();
      return;
    }
    final retained = previousPath == null
        ? -1
        : _candidates.indexWhere((file) => file.path == previousPath);
    _highlightIndex = retained >= 0 ? retained : 0;
    notifyListeners();
  }

  void move(int delta) {
    if (_candidates.isEmpty) {
      return;
    }
    final next = (_highlightIndex + delta).clamp(0, _candidates.length - 1);
    if (next == _highlightIndex) {
      return;
    }
    _highlightIndex = next;
    notifyListeners();
  }

  void reset() {
    _candidates = const <WorkspaceNode>[];
    _highlightIndex = 0;
  }
}

/// Composer 上方的 @-mention 文件候选 popover。
class _AgentMentionFilePickerPopover extends StatefulWidget {
  const _AgentMentionFilePickerPopover({
    required this.width,
    required this.maxHeight,
    required this.documentController,
    required this.listController,
    required this.candidatesFor,
    required this.onSelect,
    required this.onRequestClose,
    this.filesListenable,
    this.isIndexReady,
  });

  final double width;
  final double maxHeight;
  final ComposerDocumentController documentController;
  final _MentionFileListController listController;
  final List<WorkspaceNode> Function(String query) candidatesFor;
  final ValueChanged<WorkspaceNode> onSelect;
  final VoidCallback onRequestClose;

  /// 后台语料就绪时通知，用于在 popover 打开期间刷新候选。
  final Listenable? filesListenable;

  /// 完整文件索引是否已就绪；未注入时视为就绪。
  final bool Function()? isIndexReady;

  @override
  State<_AgentMentionFilePickerPopover> createState() =>
      _AgentMentionFilePickerPopoverState();
}

class _AgentMentionFilePickerPopoverState
    extends State<_AgentMentionFilePickerPopover> {
  @override
  void initState() {
    super.initState();
    widget.documentController.addListener(_handleDocumentChanged);
    widget.listController.addListener(_handleListChanged);
    widget.filesListenable?.addListener(_handleFilesChanged);
    _refreshCandidates();
  }

  @override
  void didUpdateWidget(covariant _AgentMentionFilePickerPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filesListenable != widget.filesListenable) {
      oldWidget.filesListenable?.removeListener(_handleFilesChanged);
      widget.filesListenable?.addListener(_handleFilesChanged);
      _refreshCandidates();
    }
  }

  @override
  void dispose() {
    widget.documentController.removeListener(_handleDocumentChanged);
    widget.listController.removeListener(_handleListChanged);
    widget.filesListenable?.removeListener(_handleFilesChanged);
    super.dispose();
  }

  void _handleDocumentChanged() {
    final query = widget.documentController.activeMentionQuery;
    if (query == null) {
      // 离开 @token 后关闭。
      widget.onRequestClose();
      return;
    }
    _refreshCandidates();
  }

  void _handleListChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 索引完成/失效时重算候选，避免 popover 卡在惰性树空结果。
  void _handleFilesChanged() {
    if (!mounted) {
      return;
    }
    _refreshCandidates();
  }

  void _refreshCandidates() {
    final query = widget.documentController.activeMentionQuery ?? '';
    widget.listController.syncCandidates(widget.candidatesFor(query));
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final candidates = widget.listController.candidates;
    final highlightIndex = widget.listController.highlightIndex;
    final indexing =
        candidates.isEmpty && !(widget.isIndexReady?.call() ?? true);

    return Semantics(
      label: 'Mention file',
      container: true,
      child: SizedBox(
        key: const ValueKey('agent-mention-picker-popover'),
        width: widget.width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: _ComposerSelectorPanel(
            child: candidates.isEmpty
                ? Padding(
                    padding: IdeSpacing.all12,
                    child: Text(
                      indexing ? 'Indexing workspace…' : 'No files found',
                      style: textStyles.bodyMedium.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      vertical: IdeSpacing.space4,
                    ),
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final file = candidates[index];
                      final highlighted = index == highlightIndex;
                      return PaneInteractiveSurface(
                        key: ValueKey('agent-mention-option-${file.path}'),
                        alignment: Alignment.centerLeft,
                        onPressed: () => widget.onSelect(file),
                        child: SizedBox(
                          width: double.infinity,
                          child: ColoredBox(
                            color: highlighted
                                ? colors.accent.withValues(alpha: 0.12)
                                : Colors.transparent,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: IdeSpacing.space10,
                                vertical: IdeSpacing.space8,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textStyles.bodyMedium.copyWith(
                                      color: colors.textPrimary,
                                      fontWeight: highlighted
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                  Text(
                                    file.path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textStyles.bodySmall.copyWith(
                                      color: colors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
