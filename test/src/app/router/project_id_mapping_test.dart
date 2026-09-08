import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/router/project_id_mapping.dart';

void main() {
  test(
    'hashPath shares workspace normalization without folding case or separators',
    () {
      const unix = '/Users/me/project';
      const windows = r'C:\Users\me\project';
      expect(
        ProjectIdMapping.hashPath(unix),
        ProjectIdMapping.hashPath('$unix/'),
      );
      expect(
        ProjectIdMapping.hashPath(windows),
        isNot(ProjectIdMapping.hashPath(r'c:/users/me/project')),
      );
      expect(
        ProjectIdMapping.hashPath(windows),
        ProjectIdMapping.hashPath(r'C:\Users\me\project\'),
      );
    },
  );

  test('projectId is 12 hex chars and does not leak the host path', () {
    const path = r'D:\secret\workspace\zeta';
    final id = ProjectIdMapping.hashPath(path);
    expect(id, matches(RegExp(r'^[0-9a-f]{12}$')));
    expect(id.contains('secret'), isFalse);
    expect(id.contains('D:'), isFalse);
    expect(id.contains(r'\'), isFalse);
    expect(id.contains('/'), isFalse);
  });

  test('syncProjects builds and recycles the bidirectional map', () {
    final mapping = ProjectIdMapping();
    mapping.syncProjects(const <String>['/alpha', '/beta']);

    final alphaId = mapping.idForPath('/alpha');
    final betaId = mapping.idForPath('/beta');
    expect(alphaId, isNotNull);
    expect(betaId, isNotNull);
    expect(alphaId, isNot(betaId));
    expect(mapping.pathForId(alphaId!), '/alpha');
    expect(mapping.allIds, unorderedEquals(<String>[alphaId, betaId!]));

    mapping.syncProjects(const <String>['/alpha']);
    expect(mapping.idForPath('/beta'), isNull);
    expect(mapping.pathForId(betaId), isNull);
    expect(mapping.allIds, unorderedEquals(<String>[alphaId]));
  });

  test('idForPath only resolves paths that were synced', () {
    final mapping = ProjectIdMapping();
    mapping.syncProjects(const <String>['/alpha']);
    expect(mapping.idForPath('/missing'), isNull);
    expect(mapping.pathForId('deadbeefdead'), isNull);
  });

  test('idForPath respects the workspace path identity', () {
    final mapping = ProjectIdMapping();
    mapping.syncProjects(const <String>[r'C:\Users\me\project']);
    expect(mapping.idForPath(r'c:/users/me/project'), isNull);
  });
}
