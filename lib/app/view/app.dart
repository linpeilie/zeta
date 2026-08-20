import 'package:flutter/widgets.dart';
import 'package:zeta/app/app_dependencies.dart';
import 'package:zeta/app/app_repositories.dart';
import 'package:zeta/app/router/routed_app.dart';

class App extends StatelessWidget {
  const App({
    required this.dependencies,
    required this.repositories,
    super.key,
  });

  final AppDependencies dependencies;
  final AppRepositories repositories;

  @override
  Widget build(BuildContext context) {
    return RoutedApp(
      dependencies: dependencies,
      repositories: repositories,
    );
  }
}
