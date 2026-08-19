import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'architecture_test_support.dart';

void main() {
  group('Provider Data integration gate', () {
    late ArchitectureWorkspace workspace;
    late Set<String> vendors;

    setUp(() {
      workspace = ArchitectureWorkspace.load();
      vendors = workspace.stringsAt([
        'layers',
        'data',
        'vendor_packages',
      ]);
    });

    test('keeps each CLI locator implementation in its declared owner', () {
      final configured = workspace.mapAt([
        'provider_data_gate',
        'locator_owners',
      ]);
      expect(configured.keys.whereType<String>().toSet(), vendors);

      final violations = <String>[];
      for (final entry in configured.entries) {
        final vendor = entry.key;
        final value = entry.value;
        if (vendor is! String || value is! YamlMap) {
          violations.add('$vendor -> invalid locator declaration');
          continue;
        }
        final symbol = value['symbol'];
        final expectedFile = value['file'];
        if (symbol is! String || expectedFile is! String) {
          violations.add('$vendor -> missing symbol/file');
          continue;
        }
        final declaration = RegExp(
          <String>[
            r'\b(?:base\s+|final\s+|sealed\s+|abstract\s+)*class\s+',
            RegExp.escape(symbol),
            r'\b',
          ].join(),
        );
        final owners = workspace.productionDartFiles
            .where(
              (file) => declaration.hasMatch(
                sourceWithoutComments(file.readAsStringSync()),
              ),
            )
            .map(workspace.relativePath)
            .toList();
        if (owners.length != 1 || owners.singleOrNull != expectedFile) {
          violations.add('$symbol -> $owners; expected $expectedFile');
        }
        if (!expectedFile.startsWith('packages/$vendor/')) {
          violations.add('$symbol -> declared outside $vendor');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'CLI locator ownership violations:\n${violations.join('\n')}',
      );
    });

    test('keeps vendor tests and fixtures inside their owning package', () {
      final violations = <String>[];
      for (final vendor in vendors) {
        final package = workspace.packages[vendor]!;
        final testRoot = Directory('${package.root.path}/test');
        for (final entity in testRoot.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) {
            continue;
          }
          final source = entity.readAsStringSync();
          for (final foreign in vendors.difference({vendor})) {
            if (source.contains('package:$foreign/') ||
                source.contains('packages/$foreign/') ||
                source.contains('packages\\$foreign\\')) {
              violations.add(
                '${workspace.relativePath(entity)} -> $foreign',
              );
            }
          }
          if (!entity.path.endsWith('.dart')) {
            continue;
          }
          for (final uri in directiveUris(source)) {
            if (uri.contains(':')) {
              continue;
            }
            final resolved = Uri.file(entity.absolute.path)
                .resolve(uri)
                .toFilePath(windows: Platform.isWindows);
            final packageRoot = normalizedPath(package.root.absolute.path);
            if (!normalizedPath(resolved).startsWith('$packageRoot/')) {
              violations.add(
                '${workspace.relativePath(entity)} -> $uri',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'Vendor tests/fixtures crossed package boundaries:\n'
            '${violations.join('\n')}',
      );
    });

    test('retains all five bounded real-CLI smoke harnesses', () {
      final scripts = workspace.stringsAt([
        'provider_data_gate',
        'smoke_scripts',
      ]);
      expect(scripts, hasLength(5));
      final missing = scripts
          .where((path) => !File('${workspace.root.path}/$path').existsSync())
          .toList();
      expect(missing, isEmpty, reason: 'Missing smoke scripts: $missing');

      final codex = File(
        '${workspace.root.path}/tool/smoke_codex_app_server.py',
      ).readAsStringSync();
      final grok = File(
        '${workspace.root.path}/tool/smoke_grok_acp.py',
      ).readAsStringSync();
      final claude = File(
        '${workspace.root.path}/tool/smoke_claude_code_metadata.py',
      ).readAsStringSync();
      expect(codex, contains('--capabilities-only'));
      expect(grok, contains('--capabilities-only'));
      expect(claude, contains('no-Prompt smoke'));
    });

    test('keeps process, stream, and subscription teardown evidence', () {
      final providerTests = <String>[
        _path(<String>[
          'packages',
          'codex_app_server_client',
          'test',
          'src',
          'datasources',
          'app_server',
          'codex_app_server_provider_test.dart',
        ]),
        _path(<String>[
          'packages',
          'claude_code_client',
          'test',
          'src',
          'datasources',
          'claude_code',
          'claude_code_agent_provider_test.dart',
        ]),
        _path(<String>[
          'packages',
          'grok_acp_client',
          'test',
          'src',
          'datasources',
          'acp',
          'grok_acp_provider_test.dart',
        ]),
      ];
      final bundleTests = <String>[
        _path(<String>[
          'packages',
          'codex_app_server_client',
          'test',
          'src',
          'codex_provider_bundle_factory_test.dart',
        ]),
        _path(<String>[
          'packages',
          'claude_code_client',
          'test',
          'src',
          'claude_provider_bundle_factory_test.dart',
        ]),
        _path(<String>[
          'packages',
          'grok_acp_client',
          'test',
          'src',
          'grok_provider_bundle_factory_test.dart',
        ]),
      ];
      final violations = <String>[];
      for (final path in providerTests) {
        final source = File('${workspace.root.path}/$path').readAsStringSync();
        if (!source.contains('provider.dispose')) {
          violations.add('$path -> missing runtime teardown');
        }
      }
      for (final path in <String>[providerTests.first, providerTests.last]) {
        final source = File('${workspace.root.path}/$path').readAsStringSync();
        if (!source.contains('subscription.cancel')) {
          violations.add('$path -> missing subscription teardown');
        }
      }
      final claudePeerTest = File(
        '${workspace.root.path}/packages/claude_code_client/test/src/'
        'datasources/claude_code/stream_json_peer_test.dart',
      ).readAsStringSync();
      if (!claudePeerTest.contains('emitsDone') ||
          !claudePeerTest.contains('await peer.close()')) {
        violations.add(
          'stream_json_peer_test.dart -> missing stream/process teardown',
        );
      }
      for (final path in bundleTests) {
        final source = File('${workspace.root.path}/$path').readAsStringSync();
        if (!source.contains('await process.exitCode')) {
          violations.add('$path -> missing real process exit assertion');
        }
      }
      for (final path in workspace.stringsAt([
        'provider_data_gate',
        'smoke_scripts',
      ])) {
        final source = File('${workspace.root.path}/$path').readAsStringSync();
        if (!source.contains('finally:') || !source.contains('.close()')) {
          violations.add('$path -> missing bounded process teardown');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Lifecycle evidence violations:\n${violations.join('\n')}',
      );
    });
  });
}

String _path(List<String> segments) => segments.join('/');
