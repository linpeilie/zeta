/// 对话消息角色。
enum AgentMessageRole { user, agent, system }

/// Agent 消息的阶段。
enum AgentMessagePhase { response, commentary, other }

/// Agent 消息的生命周期状态。
enum AgentMessageStatus { streaming, completed, other }
