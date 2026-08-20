import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:usage_statistics_repository/usage_statistics_repository.dart';
import 'package:zeta/usage_statistics/bloc/usage_statistics_bloc.dart';
import 'package:zeta/usage_statistics/bloc/usage_statistics_event.dart';
import 'package:zeta/usage_statistics/cubit/agent_usage_panel_cubit.dart';
import 'package:zeta/usage_statistics/view/usage_statistics_view.dart';

class UsageStatisticsPage extends StatelessWidget {
  const UsageStatisticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<UsageStatisticsRepository>();
    return MultiBlocProvider(
      providers: [
        BlocProvider<UsageStatisticsBloc>(
          create: (_) => UsageStatisticsBloc(
            usageStatisticsRepository: repository,
          )..add(const UsageStatisticsStarted()),
        ),
        BlocProvider<AgentUsagePanelCubit>(
          create: (_) => AgentUsagePanelCubit(
            usageStatisticsRepository: repository,
          ),
        ),
      ],
      child: const UsageStatisticsView(),
    );
  }
}
