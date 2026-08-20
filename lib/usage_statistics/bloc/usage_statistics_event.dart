import 'package:equatable/equatable.dart';
import 'package:zeta/usage_statistics/bloc/usage_statistics_state.dart';

sealed class UsageStatisticsEvent extends Equatable {
  const UsageStatisticsEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

final class UsageStatisticsStarted extends UsageStatisticsEvent {
  const UsageStatisticsStarted();
}

final class UsageStatisticsPresetChanged extends UsageStatisticsEvent {
  const UsageStatisticsPresetChanged(this.preset);

  final UsageTimePreset preset;

  @override
  List<Object?> get props => <Object?>[preset];
}

final class UsageStatisticsProjectChanged extends UsageStatisticsEvent {
  const UsageStatisticsProjectChanged(this.projectPath);

  final String? projectPath;

  @override
  List<Object?> get props => <Object?>[projectPath];
}

final class UsageStatisticsProviderChanged extends UsageStatisticsEvent {
  const UsageStatisticsProviderChanged(this.providerId);

  final String? providerId;

  @override
  List<Object?> get props => <Object?>[providerId];
}

final class UsageStatisticsModelChanged extends UsageStatisticsEvent {
  const UsageStatisticsModelChanged(this.model);

  final String? model;

  @override
  List<Object?> get props => <Object?>[model];
}

final class UsageStatisticsRankSortChanged extends UsageStatisticsEvent {
  const UsageStatisticsRankSortChanged(this.sort);

  final UsageRankSort sort;

  @override
  List<Object?> get props => <Object?>[sort];
}

final class UsageStatisticsRefreshRequested extends UsageStatisticsEvent {
  const UsageStatisticsRefreshRequested();
}

final class UsageStatisticsRepeatRefreshRequested extends UsageStatisticsEvent {
  const UsageStatisticsRepeatRefreshRequested();
}
