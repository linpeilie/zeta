part of '../agent_pane.dart';

const double _agentSlashCommandPickerPreferredWidth = 320;
const double _agentSlashCommandPickerPreferredMaxHeight = 320;

/// 斜线菜单中的固定命令。
enum _SlashCommandId { plan }

/// 斜线菜单可选项（命令或 Skill），用于跨分组键盘导航。
@immutable
sealed class _SlashMenuItem {
  const _SlashMenuItem();

  String get identity;
  String get label;
}

/// 命令项。
@immutable
final class _SlashCommandMenuItem extends _SlashMenuItem {
  const _SlashCommandMenuItem({
    required this.id,
    required this.label,
    this.selected = false,
  });

  final _SlashCommandId id;
  @override
  final String label;
  final bool selected;

  @override
  String get identity => 'command:${id.name}';
}

/// Skill 项。
@immutable
final class _SlashSkillMenuItem extends _SlashMenuItem {
  const _SlashSkillMenuItem(this.skill);

  final AgentSkillMetadata skill;

  @override
  String get identity => 'skill:${skill.path}';

  @override
  String get label => skill.label;
}

/// 斜线菜单高亮与候选状态，供 Composer 键盘与 popover 共享。
final class _SlashMenuListController extends ChangeNotifier {
  List<_SlashMenuItem> _items = const <_SlashMenuItem>[];
  int _highlightIndex = 0;

  List<_SlashMenuItem> get items => _items;

  int get highlightIndex => _highlightIndex;

  _SlashMenuItem? get highlighted {
    if (_items.isEmpty) {
      return null;
    }
    return _items[_highlightIndex.clamp(0, _items.length - 1)];
  }

  void syncItems(List<_SlashMenuItem> next) {
    final previousId = highlighted?.identity;
    _items = List<_SlashMenuItem>.unmodifiable(next);
    if (_items.isEmpty) {
      _highlightIndex = 0;
      notifyListeners();
      return;
    }
    final retained = previousId == null
        ? -1
        : _items.indexWhere((item) => item.identity == previousId);
    _highlightIndex = retained >= 0 ? retained : 0;
    notifyListeners();
  }

  void move(int delta) {
    if (_items.isEmpty) {
      return;
    }
    final next = (_highlightIndex + delta).clamp(0, _items.length - 1);
    if (next == _highlightIndex) {
      return;
    }
    _highlightIndex = next;
    notifyListeners();
  }

  void reset() {
    _items = const <_SlashMenuItem>[];
    _highlightIndex = 0;
  }
}

/// 构建斜线菜单候选：命令在前，Skills 在后；按 query 过滤。
List<_SlashMenuItem> _buildSlashMenuItems({
  required String query,
  required bool showPlanCommand,
  required bool planSelected,
  required List<AgentSkillMetadata> skills,
}) {
  final normalized = query.trim().toLowerCase();
  final items = <_SlashMenuItem>[];

  if (showPlanCommand) {
    const label = 'Plan';
    if (normalized.isEmpty || label.toLowerCase().contains(normalized)) {
      items.add(
        _SlashCommandMenuItem(
          id: _SlashCommandId.plan,
          label: label,
          selected: planSelected,
        ),
      );
    }
  }

  for (final skill in skills) {
    items.add(_SlashSkillMenuItem(skill));
  }
  return items;
}

/// Composer 上方的斜线命令菜单（命令 + Skills）。
class _AgentSlashCommandPickerPopover extends StatefulWidget {
  const _AgentSlashCommandPickerPopover({
    required this.width,
    required this.maxHeight,
    required this.documentController,
    required this.listController,
    required this.showPlanCommand,
    required this.planSelected,
    required this.skillCandidatesFor,
    required this.onSelectCommand,
    required this.onSelectSkill,
    required this.onRequestClose,
  });

  final double width;
  final double maxHeight;
  final ComposerDocumentController documentController;
  final _SlashMenuListController listController;
  final bool showPlanCommand;
  final bool planSelected;
  final List<AgentSkillMetadata> Function(String query) skillCandidatesFor;
  final ValueChanged<_SlashCommandId> onSelectCommand;
  final ValueChanged<AgentSkillMetadata> onSelectSkill;
  final VoidCallback onRequestClose;

  @override
  State<_AgentSlashCommandPickerPopover> createState() =>
      _AgentSlashCommandPickerPopoverState();
}

class _AgentSlashCommandPickerPopoverState
    extends State<_AgentSlashCommandPickerPopover> {
  @override
  void initState() {
    super.initState();
    widget.documentController.addListener(_handleDocumentChanged);
    widget.listController.addListener(_handleListChanged);
    _refreshItems();
  }

  @override
  void didUpdateWidget(covariant _AgentSlashCommandPickerPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showPlanCommand != widget.showPlanCommand ||
        oldWidget.planSelected != widget.planSelected) {
      _refreshItems();
    }
  }

  @override
  void dispose() {
    widget.documentController.removeListener(_handleDocumentChanged);
    widget.listController.removeListener(_handleListChanged);
    super.dispose();
  }

  void _handleDocumentChanged() {
    final query = widget.documentController.activeSlashQuery;
    if (query == null) {
      widget.onRequestClose();
      return;
    }
    _refreshItems();
  }

  void _handleListChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _refreshItems() {
    final query = widget.documentController.activeSlashQuery ?? '';
    final skills = widget.skillCandidatesFor(query);
    widget.listController.syncItems(
      _buildSlashMenuItems(
        query: query,
        showPlanCommand: widget.showPlanCommand,
        planSelected: widget.planSelected,
        skills: skills,
      ),
    );
  }

  void _activate(_SlashMenuItem item) {
    switch (item) {
      case final _SlashCommandMenuItem command:
        widget.onSelectCommand(command.id);
      case final _SlashSkillMenuItem skill:
        widget.onSelectSkill(skill.skill);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final items = widget.listController.items;
    final highlightIndex = widget.listController.highlightIndex;

    final commandItems = items.whereType<_SlashCommandMenuItem>().toList(
      growable: false,
    );
    final skillItems = items.whereType<_SlashSkillMenuItem>().toList(
      growable: false,
    );

    return Semantics(
      label: 'Slash commands',
      container: true,
      child: SizedBox(
        key: const ValueKey('agent-slash-command-picker-popover'),
        width: widget.width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: _ComposerSelectorPanel(
            child: items.isEmpty
                ? Padding(
                    padding: IdeSpacing.all12,
                    child: Text(
                      'No matches',
                      style: textStyles.bodyMedium.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(
                      vertical: IdeSpacing.space4,
                    ),
                    shrinkWrap: true,
                    children: <Widget>[
                      if (commandItems.isNotEmpty) ...[
                        const _SlashMenuSectionHeader(label: '命令'),
                        for (var i = 0; i < commandItems.length; i++)
                          _SlashMenuOptionRow(
                            itemKey: ValueKey(commandItems[i].identity),
                            label: commandItems[i].label,
                            highlighted: i == highlightIndex,
                            leadingIcon: Icons.alt_route_rounded,
                            trailingIcon: commandItems[i].selected
                                ? Icons.check_rounded
                                : null,
                            onPressed: () => _activate(commandItems[i]),
                          ),
                      ],
                      if (skillItems.isNotEmpty) ...[
                        const _SlashMenuSectionHeader(label: 'Skills'),
                        for (var i = 0; i < skillItems.length; i++)
                          _SlashMenuOptionRow(
                            itemKey: ValueKey(skillItems[i].identity),
                            label: skillItems[i].label,
                            // 命令项在前，Skills 高亮下标需要整体偏移。
                            highlighted:
                                commandItems.length + i == highlightIndex,
                            leadingIcon: Icons.auto_awesome_rounded,
                            onPressed: () => _activate(skillItems[i]),
                          ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SlashMenuSectionHeader extends StatelessWidget {
  const _SlashMenuSectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        IdeSpacing.space10,
        IdeSpacing.space6,
        IdeSpacing.space10,
        IdeSpacing.space4,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyles.caption.copyWith(
          color: colors.textTertiary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SlashMenuOptionRow extends StatelessWidget {
  const _SlashMenuOptionRow({
    required this.itemKey,
    required this.label,
    required this.highlighted,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
  });

  final Key itemKey;
  final String label;
  final bool highlighted;
  final VoidCallback onPressed;
  final IconData? leadingIcon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return PaneInteractiveSurface(
      key: itemKey,
      alignment: Alignment.centerLeft,
      onPressed: onPressed,
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
            child: Row(
              children: [
                if (leadingIcon != null) ...[
                  Icon(
                    leadingIcon,
                    size: 14,
                    color: highlighted ? colors.accent : colors.textSecondary,
                  ),
                  const SizedBox(width: IdeSpacing.space8),
                ],
                Expanded(
                  child: Text(
                    label,
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
                if (trailingIcon != null) ...[
                  const SizedBox(width: IdeSpacing.space8),
                  Icon(trailingIcon, size: 14, color: colors.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
