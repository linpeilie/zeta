import 'package:flutter/material.dart';
import 'package:flutter_treeview/flutter_treeview.dart' as tree;

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/features/workspace/presentation/file_node_data.dart';

class FileTreePane extends StatelessWidget {
  const FileTreePane({
    required this.controller,
    required this.projectPath,
    required this.isLoading,
    required this.onNodeTap,
    required this.onExpansionChanged,
    super.key,
  });

  final tree.TreeViewController controller;
  final String? projectPath;
  final bool isLoading;
  final ValueChanged<String> onNodeTap;
  final void Function(String key, bool expanded) onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    return Pane(
      title: 'Files',
      subtitle: projectPath == null ? null : fileName(projectPath!),
      child: Builder(
        builder: (context) {
          if (isLoading) {
            return const Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (controller.children.isEmpty) {
            return const EmptyState(text: 'No file tree');
          }
          return tree.TreeView(
            controller: controller,
            allowParentSelect: true,
            supportParentDoubleTap: false,
            onNodeTap: onNodeTap,
            onExpansionChanged: onExpansionChanged,
            nodeBuilder: (context, node) {
              final data = node.data as FileNodeData?;
              final selected = controller.selectedKey == node.key;
              return _FileTreeNodeLabel(
                label: node.label,
                isDirectory: data?.isDirectory ?? node.isParent,
                selected: selected,
              );
            },
            theme: const tree.TreeViewTheme(
              dense: true,
              iconPadding: 5,
              levelPadding: 14,
              verticalSpacing: 0,
              horizontalSpacing: 4,
              labelOverflow: TextOverflow.ellipsis,
              parentLabelOverflow: TextOverflow.ellipsis,
              iconTheme: IconThemeData(size: 15, color: ideMutedTextColor),
              expanderTheme: tree.ExpanderThemeData(
                color: ideMutedTextColor,
                size: 18,
                type: tree.ExpanderType.chevron,
              ),
              labelStyle: TextStyle(fontSize: 12),
              parentLabelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FileTreeNodeLabel extends StatelessWidget {
  const _FileTreeNodeLabel({
    required this.label,
    required this.isDirectory,
    required this.selected,
  });

  final String label;
  final bool isDirectory;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey('file-node-$label'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          children: [
            Icon(
              isDirectory ? Icons.folder_rounded : Icons.description_outlined,
              size: 15,
              color: selected
                  ? ideAccentColor
                  : isDirectory
                  ? ideWarningColor
                  : ideMutedTextColor,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : null,
                  fontSize: 12,
                  fontWeight: isDirectory ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
