import 'dart:convert';
import 'dart:io';

import 'release_metadata.dart';

/// Ordering shared by local release preparation and CI (stable > same-core beta).
final class ReleaseVersion implements Comparable<ReleaseVersion> {
  ReleaseVersion(this.core, this.beta);

  final List<int> core;
  final int? beta;

  static ReleaseVersion? tryParse(String tag) {
    final match = RegExp(
      r'^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-beta\.([1-9][0-9]*))?$',
    ).firstMatch(tag);
    if (match == null) return null;
    return ReleaseVersion([
      for (var i = 1; i <= 3; i++) int.parse(match.group(i)!),
    ], match.group(4) == null ? null : int.parse(match.group(4)!));
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < 3; i++) {
      final difference = core[i].compareTo(other.core[i]);
      if (difference != 0) return difference;
    }
    if (beta == null) return other.beta == null ? 0 : 1;
    if (other.beta == null) return -1;
    return beta!.compareTo(other.beta!);
  }
}

ReleaseMetadata readReleasePlan(String contents, String pubspec) {
  final raw = jsonDecode(contents);
  if (raw is! Map || raw['schemaVersion'] != 1 || raw['version'] is! String) {
    throw const FormatException('Invalid release.json schema.');
  }
  return ReleaseMetadata.parse(
    tag: 'v${raw['version']}',
    pubspecContents: pubspec,
  );
}

void validateReleaseProgression(String tag, Iterable<String> previousTags) {
  final target = ReleaseVersion.tryParse(tag);
  if (target == null) throw FormatException('Invalid release version: $tag');
  for (final previousTag in previousTags) {
    final previous = ReleaseVersion.tryParse(previousTag);
    if (previous != null && target.compareTo(previous) <= 0) {
      throw FormatException('$tag must be greater than $previousTag.');
    }
  }
}

String _git(List<String> arguments) {
  final result = Process.runSync('git', arguments);
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

void main(List<String> arguments) {
  try {
    String? output;
    String? previousRef;
    var allowExisting = false;
    for (var i = 0; i < arguments.length; i++) {
      switch (arguments[i]) {
        case '--github-output':
          output = arguments[++i];
        case '--previous-ref':
          previousRef = arguments[++i];
        case '--allow-existing':
          allowExisting = true;
        default:
          throw FormatException('Unknown option ${arguments[i]}');
      }
    }
    final metadata = readReleasePlan(
      File('release.json').readAsStringSync(),
      File('pubspec.yaml').readAsStringSync(),
    );
    if (_git(['rev-parse', '--is-shallow-repository']) != 'false') {
      throw StateError('Fetch complete history and tags before validation.');
    }
    final tags = _git(['tag', '--list']).split('\n');
    final head = _git(['rev-parse', 'HEAD']);
    // A retry may reuse only its own immutable identity, never another commit.
    if (allowExisting && tags.contains(metadata.tag)) {
      if (_git(['rev-parse', '${metadata.tag}^{commit}']) != head) {
        throw StateError('Existing tag points to a different commit.');
      }
      tags.remove(metadata.tag);
    }
    validateReleaseProgression(metadata.tag, tags);
    if (previousRef != null) {
      final files = _git([
        'ls-tree',
        '--name-only',
        previousRef,
        'release.json',
      ]);
      if (files.isNotEmpty) {
        final previous = readReleasePlan(
          _git(['show', '$previousRef:release.json']),
          _git(['show', '$previousRef:pubspec.yaml']),
        );
        validateReleaseProgression(metadata.tag, [previous.tag]);
      }
    }
    final notes = 'docs/zh/release/notes/${metadata.tag}.md';
    if (!File(notes).existsSync() ||
        File(notes).readAsStringSync().trim().isEmpty) {
      throw StateError('Release notes missing or empty: $notes');
    }
    final values = {
      ...metadata.toGitHubOutputs(),
      'commit': head,
      'notes': notes,
    };
    if (output != null) {
      File(output).writeAsStringSync(
        values.entries.map((entry) => '${entry.key}=${entry.value}\n').join(),
        mode: FileMode.append,
      );
    }
    stdout.writeln(jsonEncode(values));
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
