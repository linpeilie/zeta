import 'package:zeta/app/app.dart';
import 'package:zeta/bootstrap.dart';

Future<void> main() async {
  await bootstrap(
    (dependencies, composition) => App(
      dependencies: dependencies,
      repositories: composition.repositories,
    ),
  );
}
