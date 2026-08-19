import 'dart:collection';

import 'package:equatable/equatable.dart';

/// A platform-neutral system font family.
final class SystemFontFamily extends Equatable {
  /// Creates a system font family.
  SystemFontFamily({
    required this.id,
    required this.familyName,
    required this.displayName,
    required Iterable<String> aliases,
    required this.isMonospace,
  }) : aliases = UnmodifiableListView<String>(List<String>.of(aliases));

  /// Decodes the native system-font channel payload.
  static SystemFontFamily? tryDecode(Object? value) {
    if (value is! Map<Object?, Object?>) {
      return null;
    }
    final id = _nonEmptyString(value['id']);
    final familyName = _nonEmptyString(value['familyName']);
    final displayName = _nonEmptyString(value['displayName']);
    final monospace = value['monospace'];
    final rawAliases = value['aliases'];
    if (id == null ||
        familyName == null ||
        displayName == null ||
        monospace is! bool ||
        rawAliases is! List<Object?>) {
      return null;
    }
    final aliases = <String>[];
    for (final rawAlias in rawAliases) {
      final alias = _nonEmptyString(rawAlias);
      if (alias == null) {
        return null;
      }
      aliases.add(alias);
    }
    return SystemFontFamily(
      id: id,
      familyName: familyName,
      displayName: displayName,
      aliases: aliases,
      isMonospace: monospace,
    );
  }

  /// Stable platform-qualified identity.
  final String id;

  /// Canonical family name used to select the font.
  final String familyName;

  /// Localized name shown to the user.
  final String displayName;

  /// Alternative family or legacy file names.
  final List<String> aliases;

  /// Whether the platform reports a fixed-width family.
  final bool isMonospace;

  @override
  List<Object?> get props => [
    id,
    familyName,
    displayName,
    aliases,
    isMonospace,
  ];
}

/// Loads the installed desktop font catalog.
// A port intentionally groups this capability behind an injectable interface.
// ignore: one_member_abstracts
abstract interface class SystemFontCatalogApi {
  /// Returns normalized, unique families sorted by display name.
  Future<List<SystemFontFamily>> listFontFamilies({
    required String localeName,
  });
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
