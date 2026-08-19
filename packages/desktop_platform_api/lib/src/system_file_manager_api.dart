/// Opens directories using the operating system's file manager.
// A port intentionally groups this capability behind an injectable interface.
// ignore: one_member_abstracts
abstract interface class SystemFileManagerApi {
  /// Opens an existing directory at [path].
  Future<void> openDirectory(String path);
}
