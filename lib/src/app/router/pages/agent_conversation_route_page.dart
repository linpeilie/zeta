import 'package:flutter/widgets.dart';
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/pages/conversation_route_page.dart';

class AgentConversationRoutePage extends StatelessWidget {
  const AgentConversationRoutePage({
    required this.projectId,
    required this.threadId,
    super.key,
  });
  final String projectId;
  final String threadId;

  @override
  Widget build(BuildContext context) =>
      ConversationRoutePage(location: ThreadLocation(projectId, threadId));
}
