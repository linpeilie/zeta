import 'dart:collection';
import 'dart:typed_data';

import 'package:desktop_platform_api/desktop_platform_api.dart';

/// Injectable facade for the pasteboard plugin.
abstract interface class PasteboardFacade {
  /// Writes plain text.
  Future<void> writeText(String text);

  /// Reads plain text.
  Future<String?> readText();

  /// Reads image bytes.
  Future<Uint8List?> readImage();

  /// Reads file paths.
  Future<List<String>> readFiles();
}

/// Implements [ClipboardApi] through an injected pasteboard facade.
final class PasteboardClipboardAdapter implements ClipboardApi {
  /// Creates an adapter.
  const PasteboardClipboardAdapter(this._facade);

  final PasteboardFacade _facade;

  @override
  Future<List<String>> readFilePaths() async =>
      UnmodifiableListView<String>(List<String>.of(await _facade.readFiles()));

  @override
  Future<Uint8List?> readImage() async {
    final bytes = await _facade.readImage();
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<String?> readText() => _facade.readText();

  @override
  Future<void> writeText(String text) => _facade.writeText(text);
}
