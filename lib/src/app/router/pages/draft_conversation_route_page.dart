import 'package:flutter/widgets.dart';
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/pages/conversation_route_page.dart';

class DraftConversationRoutePage extends StatelessWidget {
  const DraftConversationRoutePage({
    required this.projectId,
    required this.providerId,
    super.key,
  });
  final String projectId;
  final String providerId;

  @override
  Widget build(BuildContext context) => ConversationRoutePage(
    location: DraftThreadLocation(projectId, providerId),
  );
}
