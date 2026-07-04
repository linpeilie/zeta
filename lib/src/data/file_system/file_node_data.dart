class FileNodeData {
  const FileNodeData({
    required this.path,
    required this.isDirectory,
    this.childrenLoaded = false,
  });

  final String path;
  final bool isDirectory;
  final bool childrenLoaded;
}
