import 'package:equatable/equatable.dart';
import 'package:project_session_repository/project_session_repository.dart';

sealed class IdeShellEvent extends Equatable {
  const IdeShellEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

final class IdeShellStarted extends IdeShellEvent {
  const IdeShellStarted();
}

final class IdeShellSnapshotUpdated extends IdeShellEvent {
  const IdeShellSnapshotUpdated(this.snapshot);

  final ProjectSessionSnapshot? snapshot;

  @override
  List<Object?> get props => <Object?>[snapshot];
}

final class IdeShellOpenProjectRequested extends IdeShellEvent {
  const IdeShellOpenProjectRequested();
}

final class IdeShellProjectPickedConsumed extends IdeShellEvent {
  const IdeShellProjectPickedConsumed();
}

final class IdeShellSidebarVisibilityToggled extends IdeShellEvent {
  const IdeShellSidebarVisibilityToggled();
}

final class IdeShellUsageExpandedToggled extends IdeShellEvent {
  const IdeShellUsageExpandedToggled();
}

final class IdeShellSidebarWidthChanged extends IdeShellEvent {
  const IdeShellSidebarWidthChanged(this.width);

  final double width;

  @override
  List<Object?> get props => <Object?>[width];
}

final class IdeShellUsageHeightFractionChanged extends IdeShellEvent {
  const IdeShellUsageHeightFractionChanged(this.fraction);

  final double fraction;

  @override
  List<Object?> get props => <Object?>[fraction];
}

final class IdeShellWindowMinimizeRequested extends IdeShellEvent {
  const IdeShellWindowMinimizeRequested();
}

final class IdeShellWindowMaximizeToggled extends IdeShellEvent {
  const IdeShellWindowMaximizeToggled();
}

final class IdeShellWindowCloseRequested extends IdeShellEvent {
  const IdeShellWindowCloseRequested();
}
