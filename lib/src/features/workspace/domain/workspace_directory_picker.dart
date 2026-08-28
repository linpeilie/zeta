/// 系统目录选择端口。
///
/// application 只依赖这份契约；弹原生对话框的实现住在 data 层，测试装 fake。
abstract interface class WorkspaceDirectoryPicker {
  /// 弹出系统目录选择器，返回用户选中的绝对路径。
  ///
  /// 用户取消返回 null。
  Future<String?> pickDirectory();
}
