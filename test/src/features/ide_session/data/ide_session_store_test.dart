import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';

void main() {
  group('FileIdeSessionStore', () {
    late Directory tempDirectory;
    late File sessionFile;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync(
        'zeta_ide_session_store_',
      );
      sessionFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}ide_session.json',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('returns null when the session file is missing', () async {
      final store = FileIdeSessionStore(file: sessionFile);

      expect(await store.load(), isNull);
    });

    test('saves and restores the versioned session snapshot', () async {
      final store = FileIdeSessionStore(file: sessionFile);
      const snapshot = IdeSessionState(
        projectPaths: <String>['/repo'],
        activeProjectPath: '/repo',
        activeAgentProviderId: defaultAgentProviderId,
        agentThreadIdsByProject: <String, String>{'/repo': 'thread-1'},
        workbenchLayout: IdeWorkbenchLayoutState(
          leftSidebarVisible: false,
          agentUsageExpanded: true,
          leftSidebarWidth: 310,
          agentUsageHeightFraction: 0.45,
          selectedAgentUsageProviderId: 'grok',
        ),
      );

      await store.save(snapshot);
      final restored = await store.load();
      final raw =
          jsonDecode(await sessionFile.readAsString()) as Map<String, Object?>;

      expect(raw['version'], sessionStateVersion);
      expect((raw['workbench'] as Map<String, Object?>).keys, <String>[
        'leftSidebarVisible',
        'agentUsageExpanded',
        'leftSidebarWidth',
        'agentUsageHeightFraction',
        'selectedAgentUsageProviderId',
      ]);
      expect(restored?.projectPaths, <String>['/repo']);
      expect(restored?.activeProjectPath, '/repo');
      expect(restored?.activeAgentProviderId, defaultAgentProviderId);
      expect(restored?.agentThreadIdsByProject, <String, String>{
        '/repo': 'thread-1',
      });
      expect(restored?.workbenchLayout, snapshot.workbenchLayout);
    });

    test('returns an empty snapshot when the JSON file is damaged', () async {
      await sessionFile.writeAsString('{not-json');
      final store = FileIdeSessionStore(file: sessionFile);

      final restored = await store.load();

      expect(restored, isNotNull);
      expect(restored?.projectPaths, isEmpty);
    });

    test('returns null when the file is not valid UTF-8', () async {
      await sessionFile.writeAsBytes(<int>[0xff]);
      final store = FileIdeSessionStore(file: sessionFile);

      expect(await store.load(), isNull);
    });

    test('propagates file system errors while saving', () async {
      final blockedParent = File(
        '${tempDirectory.path}${Platform.pathSeparator}blocked',
      );
      await blockedParent.writeAsString('not a directory');
      final store = FileIdeSessionStore(
        file: File(
          '${blockedParent.path}${Platform.pathSeparator}ide_session.json',
        ),
      );

      await expectLater(
        store.save(const IdeSessionState()),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
