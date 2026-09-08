import 'package:flutter/widgets.dart';
import 'package:zeta/src/app/router/app_route_context.dart';
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/pages/workbench_cover_page.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';

class SettingsRoutePage extends StatelessWidget {
  const SettingsRoutePage({required this.section, super.key});
  final SettingsSection section;

  @override
  Widget build(BuildContext context) => WorkbenchCoverPage(
    location: SettingsLocation(section),
    navigationPane: SettingsNavigationPane(
      activeSection: section,
      showAgentManagement: true,
      onSectionSelected: (next) {
        if (next != section) context.replaceLocation(SettingsLocation(next));
      },
    ),
    child: SettingsPageCanvas(
      activeSection: section,
      showAgentManagement: true,
    ),
  );
}
