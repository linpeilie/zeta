import 'dart:collection';

import 'package:equatable/equatable.dart';

/// A platform-neutral file-type filter.
final class FileTypeFilter extends Equatable {
  /// Creates a file-type filter.
  FileTypeFilter({
    required this.label,
    Iterable<String> extensions = const <String>[],
    Iterable<String> mimeTypes = const <String>[],
    Iterable<String> uniformTypeIdentifiers = const <String>[],
  }) : extensions = _snapshot(extensions),
       mimeTypes = _snapshot(mimeTypes),
       uniformTypeIdentifiers = _snapshot(uniformTypeIdentifiers);

  /// User-visible filter label.
  final String label;

  /// File extensions without a leading dot.
  final List<String> extensions;

  /// MIME types accepted by platforms that support them.
  final List<String> mimeTypes;

  /// Uniform Type Identifiers accepted by Apple platforms.
  final List<String> uniformTypeIdentifiers;

  @override
  List<Object?> get props => [
    label,
    extensions,
    mimeTypes,
    uniformTypeIdentifiers,
  ];
}

/// Selects one or more files without exposing plugin file types.
// A port intentionally groups this capability behind an injectable interface.
// ignore: one_member_abstracts
abstract interface class FilePickerApi {
  /// Returns selected absolute file paths, or an empty list when cancelled.
  Future<List<String>> pickFiles({
    List<FileTypeFilter> acceptedTypes = const <FileTypeFilter>[],
  });
}

/// Selects a directory without exposing Flutter plugin types.
// A port intentionally groups this capability behind an injectable interface.
// ignore: one_member_abstracts
abstract interface class DirectoryPickerApi {
  /// Returns the selected path, or `null` when cancelled.
  Future<String?> pickDirectory({String? initialDirectory});
}

List<String> _snapshot(Iterable<String> values) =>
    UnmodifiableListView<String>(List<String>.of(values));
