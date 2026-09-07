import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';

void main() {
  group('toPath / parse round-trip', () {
    const locations = <AppRouteLocation>[
      GlobalHomeLocation(),
      ProjectHomeLocation('aaaaaaaaaaaa'),
      DraftThreadLocation('aaaaaaaaaaaa', 'codex'),
      ThreadLocation('aaaaaaaaaaaa', '550e8400-e29b-41d4-a716-446655440000'),
      SettingsLocation(SettingsSection.general),
      SettingsLocation(SettingsSection.appearance),
      SettingsLocation(SettingsSection.agents),
    ];

    for (final location in locations) {
      test('${location.runtimeType} ${location.toPath()}', () {
        expect(parseAppRouteLocation(Uri.parse(location.toPath())), location);
      });
    }
  });

  test('empty and root parse as global home', () {
    expect(parseAppRouteLocation(Uri.parse('')), const GlobalHomeLocation());
    expect(parseAppRouteLocation(Uri.parse('/')), const GlobalHomeLocation());
  });

  test('unknown first segment falls back to global home', () {
    expect(
      parseAppRouteLocation(Uri.parse('/not-a-route')),
      const GlobalHomeLocation(),
    );
    expect(
      parseAppRouteLocation(Uri.parse('/project/id/extra')),
      const GlobalHomeLocation(),
    );
  });

  test('illegal id charset falls back to a legal parent location', () {
    expect(
      parseAppRouteLocation(Uri.parse('/project/has.dot')),
      const GlobalHomeLocation(),
    );
    expect(
      parseAppRouteLocation(Uri.parse('/project/aaaaaaaaaaaa/draft/bad.id')),
      const ProjectHomeLocation('aaaaaaaaaaaa'),
    );
    expect(
      parseAppRouteLocation(Uri.parse('/project/aaaaaaaaaaaa/thread/bad.id')),
      const ProjectHomeLocation('aaaaaaaaaaaa'),
    );
  });

  test('bare settings and illegal section parse as general', () {
    expect(
      parseAppRouteLocation(Uri.parse('/settings')),
      const SettingsLocation(SettingsSection.general),
    );
    expect(
      parseAppRouteLocation(Uri.parse('/settings/nope')),
      const SettingsLocation(SettingsSection.general),
    );
  });

  test('query string does not change path identity', () {
    expect(
      parseAppRouteLocation(Uri.parse('/project/aaaaaaaaaaaa?x=1')),
      const ProjectHomeLocation('aaaaaaaaaaaa'),
    );
  });

  test('location equality is by fields', () {
    expect(
      const ProjectHomeLocation('aaaaaaaaaaaa'),
      const ProjectHomeLocation('aaaaaaaaaaaa'),
    );
    expect(
      const ProjectHomeLocation('aaaaaaaaaaaa'),
      isNot(const ProjectHomeLocation('bbbbbbbbbbbb')),
    );
    expect(const GlobalHomeLocation(), const GlobalHomeLocation());
  });
}
