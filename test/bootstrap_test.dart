import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/bootstrap.dart';
import 'package:zeta/counter/counter.dart';

void main() {
  testWidgets('freezes supported locale dependencies before app creation', (
    tester,
  ) async {
    final apps = <Widget>[];
    late Locale frozenLocale;

    await bootstrap(
      (dependencies) {
        frozenLocale = dependencies.locale;
        expect(
          dependencies.desktopNotificationCopyResolver.linuxActionName,
          '打开 Zeta',
        );
        return const SizedBox();
      },
      platformLocale: const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
      ),
      appRunner: apps.add,
    );

    expect(
      frozenLocale,
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
      ),
    );
    expect(apps, hasLength(1));
  });

  testWidgets('uses the platform locale and accepts an async builder', (
    tester,
  ) async {
    final apps = <Widget>[];

    await bootstrap(
      (dependencies) async {
        expect(dependencies.locale.languageCode, isNotEmpty);
        return const SizedBox();
      },
      appRunner: apps.add,
    );

    expect(apps, hasLength(1));
  });

  test('observer forwards changes and errors', () async {
    const observer = AppBlocObserver();
    final cubit = CounterCubit();
    final error = StateError('expected');

    observer
      ..onChange(cubit, const Change<int>(currentState: 0, nextState: 1))
      ..onError(cubit, error, StackTrace.empty);

    expect(Bloc.observer, isA<AppBlocObserver>());
    await cubit.close();
  });

  testWidgets('bootstrap error handler accepts Flutter errors', (tester) async {
    await bootstrap(
      (_) => const SizedBox(),
      platformLocale: const Locale('en'),
      appRunner: (_) {},
    );

    FlutterError.onError!(
      FlutterErrorDetails(
        exception: FlutterError('expected'),
        stack: StackTrace.empty,
      ),
    );
  });
}
