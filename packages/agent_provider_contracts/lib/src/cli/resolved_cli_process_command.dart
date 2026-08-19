import 'package:equatable/equatable.dart';

/// Complete command ready for a process starter.
final class ResolvedCliProcessCommand extends Equatable {
  ResolvedCliProcessCommand({
    required this.executable,
    required Iterable<String> arguments,
    this.displayPath,
  }) : arguments = List<String>.unmodifiable(arguments);

  final String executable;
  final List<String> arguments;

  /// Optional user-configured path for diagnostics, never executable logic.
  final String? displayPath;

  /// Returns a new command with protocol arguments appended.
  ResolvedCliProcessCommand processCommandFor(
    Iterable<String> protocolArguments,
  ) {
    return ResolvedCliProcessCommand(
      executable: executable,
      arguments: <String>[...arguments, ...protocolArguments],
      displayPath: displayPath,
    );
  }

  @override
  List<Object?> get props => [executable, arguments, displayPath];
}
