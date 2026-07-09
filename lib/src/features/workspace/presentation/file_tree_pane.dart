import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

class FileTreePane extends StatelessWidget {
  const FileTreePane({
    required this.nodes,
    required this.expandedPaths,
    required this.selectedPath,
    required this.projectPath,
    required this.isLoading,
    required this.onNodeTap,
    required this.onExpansionChanged,
    super.key,
  });

  final List<WorkspaceNode> nodes;
  final Set<String> expandedPaths;
  final String? selectedPath;
  final String? projectPath;
  final bool isLoading;
  final ValueChanged<String> onNodeTap;
  final void Function(String key, bool expanded) onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    String title = "Files";
    if (projectPath != null) {
      title = 'Files • ${fileName(projectPath!)}';
    }
    return Pane(
      title: title,
      child: Builder(
        builder: (context) {
          if (isLoading) {
            return Center(
              child: IdeLoadingIndicator(width: 24, height: 12, barHeight: 4),
            );
          }
          if (nodes.isEmpty) {
            return const EmptyState(text: 'No file tree');
          }
          final visibleNodes = _flattenVisibleNodes(nodes, expandedPaths);
          return ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: IdeSpacing.space6,
              vertical: IdeSpacing.space6,
            ),
            itemCount: visibleNodes.length,
            itemBuilder: (context, index) {
              final visibleNode = visibleNodes[index];
              return _FileTreeNodeTile(
                key: ValueKey<String>(
                  'file-node-path-${visibleNode.node.path}',
                ),
                node: visibleNode.node,
                depth: visibleNode.depth,
                expanded: visibleNode.expanded,
                selected: selectedPath == visibleNode.node.path,
                onTap: () => onNodeTap(visibleNode.node.path),
                onToggleExpansion: visibleNode.node.isDirectory
                    ? () => onExpansionChanged(
                        visibleNode.node.path,
                        !visibleNode.expanded,
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

List<_VisibleWorkspaceNode> _flattenVisibleNodes(
  Iterable<WorkspaceNode> nodes,
  Set<String> expandedPaths, {
  int depth = 0,
}) {
  final visibleNodes = <_VisibleWorkspaceNode>[];
  for (final node in nodes) {
    final expanded = node.isDirectory && expandedPaths.contains(node.path);
    visibleNodes.add(
      _VisibleWorkspaceNode(node: node, depth: depth, expanded: expanded),
    );
    if (expanded && node.children.isNotEmpty) {
      visibleNodes.addAll(
        _flattenVisibleNodes(node.children, expandedPaths, depth: depth + 1),
      );
    }
  }
  return visibleNodes;
}

class _VisibleWorkspaceNode {
  const _VisibleWorkspaceNode({
    required this.node,
    required this.depth,
    required this.expanded,
  });

  final WorkspaceNode node;
  final int depth;
  final bool expanded;
}

class _FileTreeNodeTile extends StatelessWidget {
  const _FileTreeNodeTile({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.selected,
    required this.onTap,
    required this.onToggleExpansion,
    super.key,
  });

  static const double _rowHeight = 28;
  static const double _indent = IdeSpacing.space16;

  final WorkspaceNode node;
  final int depth;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onToggleExpansion;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final selectedBackground = colors.primaryMuted;
    final hoverBackground = colors.border.withValues(alpha: 0.14);
    final iconColor = selected
        ? colors.accent
        : node.isDirectory
        ? colors.accent.withValues(alpha: 0.82)
        : colors.textSecondary;
    final textColor = selected ? colors.accent : colors.textPrimary;

    return Padding(
      padding: EdgeInsets.only(left: depth * _indent),
      child: PaneInteractiveSurface(
        key: ValueKey<String>('file-node-${node.name}'),
        onPressed: onTap,
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space6),
        selected: selected,
        selectedBackgroundColor: selectedBackground,
        hoverBackgroundColor: hoverBackground,
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: node.isDirectory
                  ? sf.IconButton.ghost(
                      onPressed: onToggleExpansion,
                      size: sf.ButtonSize.xSmall,
                      density: sf.ButtonDensity.iconDense,
                      icon: Icon(
                        expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.chevron_right_rounded,
                        size: 14,
                        color: colors.textSecondary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 2),
            Icon(
              node.isDirectory
                  ? Icons.folder_rounded
                  : Icons.insert_drive_file_outlined,
              size: 15,
              color: iconColor,
            ),
            const SizedBox(width: IdeSpacing.space6),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyles.bodySmall.copyWith(
                  color: textColor,
                  fontWeight: node.isDirectory
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
