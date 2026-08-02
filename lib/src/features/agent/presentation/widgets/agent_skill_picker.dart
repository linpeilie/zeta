part of '../agent_pane.dart';

const double _agentSkillPickerPreferredWidth = 320;
const double _agentSkillPickerPreferredMaxHeight = 280;

/// Skill 列表的高亮与候选状态，供 Composer 键盘与 popover 共享。
final class _SkillPickerListController extends ChangeNotifier {
  List<AgentSkillMetadata> _candidates = const <AgentSkillMetadata>[];
  int _highlightIndex = 0;

  List<AgentSkillMetadata> get candidates => _candidates;

  int get highlightIndex => _highlightIndex;

  AgentSkillMetadata? get highlighted {
    if (_candidates.isEmpty) {
      return null;
    }
    return _candidates[_highlightIndex.clamp(0, _candidates.length - 1)];
  }

  void syncCandidates(List<AgentSkillMetadata> next) {
    final previousPath = highlighted?.path;
    _candidates = List<AgentSkillMetadata>.unmodifiable(next);
    if (_candidates.isEmpty) {
      _highlightIndex = 0;
      notifyListeners();
      return;
    }
    final retained = previousPath == null
        ? -1
        : _candidates.indexWhere((skill) => skill.path == previousPath);
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
    _candidates = const <AgentSkillMetadata>[];
    _highlightIndex = 0;
  }
}

/// Composer 上方的 Skill 候选 popover。
class _AgentSkillPickerPopover extends StatefulWidget {
  const _AgentSkillPickerPopover({
    required this.width,
    required this.maxHeight,
    required this.documentController,
    required this.listController,
    required this.candidatesFor,
    required this.onSelect,
    required this.onRequestClose,
  });

  final double width;
  final double maxHeight;
  final ComposerDocumentController documentController;
  final _SkillPickerListController listController;
  final List<AgentSkillMetadata> Function(String query) candidatesFor;
  final ValueChanged<AgentSkillMetadata> onSelect;
  final VoidCallback onRequestClose;

  @override
  State<_AgentSkillPickerPopover> createState() =>
      _AgentSkillPickerPopoverState();
}

class _AgentSkillPickerPopoverState extends State<_AgentSkillPickerPopover> {
  @override
  void initState() {
    super.initState();
    widget.documentController.addListener(_handleDocumentChanged);
    widget.listController.addListener(_handleListChanged);
    _refreshCandidates();
  }

  @override
  void dispose() {
    widget.documentController.removeListener(_handleDocumentChanged);
    widget.listController.removeListener(_handleListChanged);
    super.dispose();
  }

  void _handleDocumentChanged() {
    final query = widget.documentController.activeSkillQuery;
    if (query == null) {
      // 离开 `$query` 后关闭；菜单触发也会先写入 `$`，正常路径不会立刻为空。
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

  void _refreshCandidates() {
    final query = widget.documentController.activeSkillQuery ?? '';
    widget.listController.syncCandidates(widget.candidatesFor(query));
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final candidates = widget.listController.candidates;
    final highlightIndex = widget.listController.highlightIndex;

    return Semantics(
      label: 'Insert skill',
      container: true,
      child: SizedBox(
        key: const ValueKey('agent-skill-picker-popover'),
        width: widget.width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: _ComposerSelectorPanel(
            child: candidates.isEmpty
                ? Padding(
                    padding: IdeSpacing.all12,
                    child: Text(
                      'No skills found',
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
                      final skill = candidates[index];
                      final highlighted = index == highlightIndex;
                      return PaneInteractiveSurface(
                        key: ValueKey('agent-skill-option-${skill.path}'),
                        alignment: Alignment.centerLeft,
                        onPressed: () => widget.onSelect(skill),
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
                              child: Text(
                                skill.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.left,
                                style: textStyles.bodyMedium.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: highlighted
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
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
