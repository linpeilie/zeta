import 'dart:typed_data';

/// Reads and writes desktop clipboard content.
abstract interface class ClipboardApi {
  /// Writes plain text.
  Future<void> writeText(String text);

  /// Reads plain text, or `null` if the clipboard has none.
  Future<String?> readText();

  /// Reads image bytes, or `null` if the clipboard has no image.
  Future<Uint8List?> readImage();

  /// Reads copied file paths.
  Future<List<String>> readFilePaths();
}
