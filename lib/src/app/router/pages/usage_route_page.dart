import 'package:flutter/widgets.dart';
import 'package:zeta/src/app/router/app_route_context.dart';
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/pages/workbench_cover_page.dart';
import 'package:zeta/src/features/settings/domain/settings_section.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_page.dart';

class UsageRoutePage extends StatelessWidget {
  const UsageRoutePage({super.key});

  @override
  Widget build(BuildContext context) => WorkbenchCoverPage(
    location: const UsageLocation(),
    child: UsageStatisticsPage(
      key: const ValueKey('usage-statistics-page-host'),
      onOpenAgentManagement: () => context.replaceLocation(
        const SettingsLocation(SettingsSection.agents),
      ),
    ),
  );
}
