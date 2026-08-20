import 'package:flutter/material.dart';
import 'package:zeta/app/app_dependencies.dart';
import 'package:zeta/app/app_repositories.dart';
import 'package:zeta/app/router/routed_app.dart';
import 'package:zeta/counter/counter.dart';
import 'package:zeta/l10n/l10n.dart';

class App extends StatelessWidget {
  const App({
    required this.dependencies,
    this.repositories,
    super.key,
  });

  final AppDependencies dependencies;
  final AppRepositories? repositories;

  @override
  Widget build(BuildContext context) {
    final repositories = this.repositories;
    if (repositories == null) {
      return MaterialApp(
        theme: ThemeData(
          appBarTheme: AppBarTheme(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          ),
          useMaterial3: true,
        ),
        localizationsDelegates: const [
          ZetaShadcnLocalizations.delegate,
          ...AppLocalizations.localizationsDelegates,
        ],
        locale: dependencies.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CounterPage(),
      );
    }
    return RoutedApp(
      dependencies: dependencies,
      repositories: repositories,
    );
  }
}
