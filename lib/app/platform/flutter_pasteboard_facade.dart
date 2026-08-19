import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';
import 'package:zeta/app/platform/pasteboard_clipboard_adapter.dart';

/// Production facade over `pasteboard` static APIs.
final class FlutterPasteboardFacade implements PasteboardFacade {
  /// Creates a facade with optionally injected plugin entrypoints.
  FlutterPasteboardFacade({
    Future<List<String>> Function()? readFiles,
    Future<Uint8List?> Function()? readImage,
    Future<String?> Function()? readText,
    Future<void> Function(String text)? writeText,
  }) : _readFiles = readFiles ?? Pasteboard.files,
       _readImage = readImage ?? _readPasteboardImage,
       _readText = readText ?? _readPasteboardText,
       _writeText = writeText ?? _writePasteboardText;

  final Future<List<String>> Function() _readFiles;
  final Future<Uint8List?> Function() _readImage;
  final Future<String?> Function() _readText;
  final Future<void> Function(String text) _writeText;

  @override
  Future<List<String>> readFiles() => _readFiles();

  @override
  Future<Uint8List?> readImage() => _readImage();

  @override
  Future<String?> readText() => _readText();

  @override
  Future<void> writeText(String text) => _writeText(text);
}

Future<Uint8List?> _readPasteboardImage() => Pasteboard.image;

Future<String?> _readPasteboardText() => Pasteboard.text;

Future<void> _writePasteboardText(String text) async =>
    Pasteboard.writeText(text);
