import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:zeta/ide_session/cubit/ide_session_cubit.dart';
import 'package:zeta/ide_session/view/ide_session_view.dart';

class IdeSessionPage extends StatelessWidget {
  const IdeSessionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = IdeSessionCubit(
          projectSessionRepository: context.read<ProjectSessionRepository>(),
        );
        unawaited(cubit.restore());
        return cubit;
      },
      child: const IdeSessionView(),
    );
  }
}
