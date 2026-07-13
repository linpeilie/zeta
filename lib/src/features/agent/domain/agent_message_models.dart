/// 对话消息角色。
enum AgentMessageRole { user, agent, system }

/// Agent 消息的阶段。
///
/// - [response]：回合终端汇总（Codex `phase=final_answer` 及历史别名）。
/// - [commentary]：回合中的中间叙述（Codex `phase=commentary`）。
/// - [other]：未知或未识别 phase。
enum AgentMessagePhase { response, commentary, other }

/// Agent 消息的生命周期状态。
enum AgentMessageStatus { streaming, completed, other }
