import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zeta/ide_shell/ide_shell.dart';
import 'package:zeta/l10n/l10n.dart';

import '../../helpers/helpers.dart';

class _MockIdeShellBloc extends MockBloc<IdeShellEvent, IdeShellState>
    implements IdeShellBloc {}

void main() {
  group(IdeShellView, () {
    late IdeShellBloc bloc;

    setUp(() {
      bloc = _MockIdeShellBloc();
      when(() => bloc.state).thenReturn(const IdeShellState());
    });

    testWidgets('hides the project sidebar on home', (tester) async {
      await tester.pumpApp(
        BlocProvider<IdeShellBloc>.value(
          value: bloc,
          child: const IdeShellView(child: SizedBox()),
        ),
      );
      expect(find.byKey(const Key('ide-shell-sidebar')), findsNothing);
      expect(find.byKey(const Key('ide-shell-home')), findsOneWidget);
    });

    testWidgets('toggles sidebar and usage from the shell chrome', (
      tester,
    ) async {
      await tester.pumpApp(
        BlocProvider<IdeShellBloc>.value(
          value: bloc,
          child: const IdeShellView(child: SizedBox()),
        ),
      );
      await tester.tap(find.byKey(const Key('ide-shell-toggle-sidebar')));
      await tester.tap(find.byKey(const Key('ide-shell-toggle-usage')));
      await tester.tap(find.byKey(const Key('ide-shell-open-project')));
      verify(
        () => bloc.add(const IdeShellSidebarVisibilityToggled()),
      ).called(1);
      verify(() => bloc.add(const IdeShellUsageExpandedToggled())).called(1);
      verify(() => bloc.add(const IdeShellOpenProjectRequested())).called(1);
    });

    testWidgets('opens a project from the home page', (tester) async {
      await tester.pumpApp(
        BlocProvider<IdeShellBloc>.value(
          value: bloc,
          child: const IdeHomePage(),
        ),
      );
      await tester.tap(find.byKey(const Key('ide-home-open-project')));
      verify(() => bloc.add(const IdeShellOpenProjectRequested())).called(1);
    });

    testWidgets('uses show copy when the sidebar is hidden', (tester) async {
      when(() => bloc.state).thenReturn(
        const IdeShellState(
          workbench: ProjectWorkbenchSnapshot(leftSidebarVisible: false),
        ),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(
        BlocProvider<IdeShellBloc>.value(
          value: bloc,
          child: const IdeShellView(child: SizedBox()),
        ),
      );
      expect(find.text(l10n.workbenchShowLeftSidebar), findsOneWidget);
    });
  });
}
