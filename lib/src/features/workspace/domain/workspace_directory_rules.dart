/// 工作区文件树默认忽略的目录名。
///
/// 这里仅表达领域规则本身，不涉及任何 `dart:io` 或 UI 表示。
const Set<String> ignoredWorkspaceEntryNames = {
  '.dart_tool',
  '.git',
  '.idea',
  '.vscode',
  'build',
  'node_modules',
};

/// 判断目录项名称是否需要从工作区文件树中过滤掉。
bool isIgnoredWorkspaceEntryName(String name) {
  return ignoredWorkspaceEntryNames.contains(name);
}
