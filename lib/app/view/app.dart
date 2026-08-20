import 'package:flutter/material.dart';
import 'package:zeta/app/app_dependencies.dart';
import 'package:zeta/counter/counter.dart';
import 'package:zeta/l10n/l10n.dart';

class App extends StatelessWidget {
  const App({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
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
}
