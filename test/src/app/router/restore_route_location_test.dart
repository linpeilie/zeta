import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/app/router/restore_route_location.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';

void main() {
  late ProjectIdMapping mapping;
  late String projectId;

  setUp(() {
    mapping = ProjectIdMapping()..syncProjects(const <String>['/repo']);
    projectId = mapping.idForPath('/repo')!;
  });

  group('canonicalLocationAfterRestore', () {
    test('no active project stays on global home', () {
      expect(
        canonicalLocationAfterRestore(
          activeProjectPath: null,
          mapping: mapping,
        ),
        const GlobalHomeLocation(),
      );
    });

    test('active project goes to project home, not the last thread', () {
      expect(
        canonicalLocationAfterRestore(
          activeProjectPath: '/repo',
          mapping: mapping,
        ),
        ProjectHomeLocation(projectId),
      );
    });

    test('unknown path stays on global home', () {
      expect(
        canonicalLocationAfterRestore(
          activeProjectPath: '/missing',
          mapping: mapping,
        ),
        const GlobalHomeLocation(),
      );
    });
  });

  group('restoreReplaceTarget', () {
    final canonical = ProjectHomeLocation('aaaaaaaaaaaa');

    test('does nothing until restore completes', () {
      expect(
        restoreReplaceTarget(
          current: const GlobalHomeLocation(),
          restoreCompleted: false,
          canonical: canonical,
        ),
        isNull,
      );
    });

    test('replaces global home with project home after restore', () {
      expect(
        restoreReplaceTarget(
          current: const GlobalHomeLocation(),
          restoreCompleted: true,
          canonical: canonical,
        ),
        canonical,
      );
    });

    test('does not clobber a deep link that already left home', () {
      expect(
        restoreReplaceTarget(
          current: ThreadLocation('aaaaaaaaaaaa', 'tid'),
          restoreCompleted: true,
          canonical: canonical,
        ),
        isNull,
      );
      expect(
        restoreReplaceTarget(
          current: const SettingsLocation(SettingsSection.general),
          restoreCompleted: true,
          canonical: canonical,
        ),
        isNull,
      );
    });

    test('stays put when canonical is still global home', () {
      expect(
        restoreReplaceTarget(
          current: const GlobalHomeLocation(),
          restoreCompleted: true,
          canonical: const GlobalHomeLocation(),
        ),
        isNull,
      );
    });
  });
}
