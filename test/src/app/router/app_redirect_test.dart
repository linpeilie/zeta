import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/router/app_redirect.dart';

const _projectId = 'aaaaaaaaaaaa';
const _providers = <String>{'codex', 'grok', 'claude_code'};

AppRouteSnapshot _snapshot({
  bool restoreCompleted = true,
  Set<String> projectIds = const <String>{_projectId},
  Set<String> providerIds = _providers,
}) {
  return AppRouteSnapshot(
    restoreCompleted: restoreCompleted,
    projectIds: projectIds,
    providerIds: providerIds,
  );
}

String? _redirect(String location, {AppRouteSnapshot? snapshot}) {
  return resolveAppRedirect(
    location: location,
    snapshot: snapshot ?? _snapshot(),
  );
}

void main() {
  group('restore incomplete', () {
    test('already at global home stays', () {
      expect(
        _redirect('/', snapshot: _snapshot(restoreCompleted: false)),
        isNull,
      );
    });

    test('any other location normalizes to global home', () {
      const pending = AppRouteSnapshot(
        restoreCompleted: false,
        projectIds: {_projectId},
        providerIds: _providers,
      );
      expect(_redirect('/settings/general', snapshot: pending), '/');
      expect(_redirect('/project/$_projectId', snapshot: pending), '/');
      expect(
        _redirect('/project/$_projectId/thread/tid', snapshot: pending),
        '/',
      );
      expect(
        _redirect('/project/$_projectId/draft/codex', snapshot: pending),
        '/',
      );
      expect(_redirect('/not-a-route', snapshot: pending), '/');
    });
  });

  group('settings', () {
    test('bare settings redirects to general', () {
      expect(_redirect('/settings'), '/settings/general');
      expect(_redirect('/settings/'), '/settings/general');
    });

    test('illegal section redirects to general', () {
      expect(_redirect('/settings/nope'), '/settings/general');
    });

    test('legal section does not redirect', () {
      expect(_redirect('/settings/general'), isNull);
      expect(_redirect('/settings/appearance'), isNull);
      expect(_redirect('/settings/agents'), isNull);
    });
  });

  group('project existence', () {
    test('unknown projectId on all project routes goes home', () {
      expect(_redirect('/project/deadbeefdead'), '/');
      expect(_redirect('/project/deadbeefdead/thread/tid'), '/');
      expect(_redirect('/project/deadbeefdead/draft/codex'), '/');
    });

    test('known project home and thread stay', () {
      expect(_redirect('/project/$_projectId'), isNull);
      expect(_redirect('/project/$_projectId/thread/tid'), isNull);
    });

    test('known project unknown provider falls back to project home', () {
      expect(
        _redirect('/project/$_projectId/draft/not-a-provider'),
        '/project/$_projectId',
      );
    });

    test('known project known provider draft stays', () {
      expect(_redirect('/project/$_projectId/draft/codex'), isNull);
      expect(_redirect('/project/$_projectId/draft/claude_code'), isNull);
    });

    test('illegal charset on nested ids canonicalizes to parent', () {
      expect(
        _redirect('/project/$_projectId/draft/bad.id'),
        '/project/$_projectId',
      );
      expect(
        _redirect('/project/$_projectId/thread/bad.id'),
        '/project/$_projectId',
      );
    });
  });

  test('global home stays; unknown paths normalize without looping', () {
    expect(_redirect('/'), isNull);
    expect(_redirect('/not-a-route'), '/');
    expect(_redirect('/project/has.dot'), '/');
  });
}
