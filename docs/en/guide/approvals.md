# Approvals, Questions and Plans

Requests for your response appear above the input box. Check whether the assistant needs permission for an operation, more information, or your agreement to a plan.

## Approve an operation

Permission cards request actions such as running commands or changing files. They show the details supplied by the assistant. Before allowing an action, check that its files and effects match your task.

“Deny” refuses that action. Some assistants also offer to remember a decision for the conversation or for longer. Use these only when you understand their scope; read the card's description.

Whether an operation asks each time depends on the chosen permission mode. Automatic-edit or full-access settings may allow actions directly. Accepting a plan does not make permissions broader.

A card may disappear when its request ends, expires or loses its connection. Check the conversation status; disappearance alone does not mean approval.

## Choose permissions

The permission options near the input box determine what the assistant may do.

| Common option | Meaning |
| --- | --- |
| Read only / Plan | For reviewing and planning, with changes restricted; exact permitted actions depend on the assistant |
| Workspace write / Accept edits | Allows some file changes; other confirmations depend on the assistant |
| Full access / Bypass permissions / Always approve | Relaxes or skips some checks; read the option's description first |

Modes with similar names are not necessarily equivalent across assistants. The interface explains when a change takes effect.

## Answer questions

Question cards ask for information, such as a preference or choice of approach. Select an answer or use the free-text field when available. Review multiple questions before submitting.

Skipping may let the assistant continue with existing information, or it may ask again. Answering a question does not authorize commands or file changes.

## Ask for a plan

Choose `Plan` from the `/` menu to review an approach first. For Claude Code, use Plan in the permission options. Describe the problem and any limits.

You can add requirements and ask the assistant to revise the plan. Some assistants show an “Accept plan” card; Codex has no separate card for this step.

Accepting agrees to the approach. Execution still follows the effective permissions, and actions requiring approval will still ask.

## Start the plan

When an execution confirmation appears, review the plan and permissions before starting. It normally reuses your still-valid choice from before planning. If that choice is no longer usable, it selects a conservative option supplied by the assistant or asks you to choose again.

A choice marked for this execution only is not saved for future tasks. Starting creates a new execution turn. You can also continue planning without starting it.

[Desktop notifications](notifications.md) can bring you back when a conversation is waiting for a response.
