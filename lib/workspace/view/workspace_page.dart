import 'dart:async';

import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/workspace/cubit/workspace_cubit.dart';
import 'package:zeta/workspace/view/workspace_view.dart';

class WorkspacePage extends StatelessWidget {
  const WorkspacePage({this.initialRootPath, super.key});

  final String? initialRootPath;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = WorkspaceCubit(
          workspaceRepository: context.read<WorkspaceRepository>(),
          desktopPlatformRepository: context.read<DesktopPlatformRepository>(),
        );
        final root = initialRootPath;
        if (root != null) {
          unawaited(cubit.index(root));
        }
        return cubit;
      },
      child: const WorkspaceView(),
    );
  }
}
