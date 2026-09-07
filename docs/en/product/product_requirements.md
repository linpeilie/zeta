# Product Requirements

English ｜ [中文](../../zh/product/product_requirements.md)

Zeta gives people using locally installed AI coding assistants a desktop interface for projects, conversations and requests that need a response.

## Main needs

| Need | Observable result |
| --- | --- |
| Find projects and earlier conversations | Open a local folder and start or resume a supported conversation |
| Understand the assistant's work | Replies, operations, reported edits and task status appear in time order |
| Control a task | Cancel, choose permissions, and allow or refuse requested operations |
| Review an approach first | Ask for a plan, revise it, then decide whether to execute; accepting does not expand permissions |
| Work elsewhere temporarily | Return from settings or usage with the conversation, draft and reading position preserved |
| Respond in time | Receive completion or waiting reminders away from the conversation and open it from a notification |
| Understand usage | Filter existing records by date, assistant, model and project, with missing data identified |
| Adjust reading | Choose theme, fonts, sizes and English or Simplified Chinese |

## Scope

Zeta connects Codex, Grok and Claude Code. Features differ and unsupported controls are hidden. The [assistant guide](../guide/agents.md) maintains the feature comparison.

Zeta does not include a model, code editor, cloud conversation sync or mobile app. Users supply the assistant and account. Assistants make file changes; cancelling or branching does not undo them.

## Data and recovery

Zeta keeps settings, project lists and usage summaries locally. Recovery depends on project folders and assistant history still existing. It cannot promise to recover deleted data. Unsent drafts are for the current run and are not guaranteed after exit.

Local operation does not mean offline processing: an assistant may send content to model services. Documentation must distinguish Zeta's records, the assistant's history and content sent outside the computer. See [Data and Privacy](../guide/data-and-privacy.md).

## Acceptance criteria

- Complete opening a project, sending, responding, cancelling and resuming on supported systems.
- Correct status across projects and background tasks; page switches leave tasks running.
- Permission descriptions match their effects. Plan acceptance is not authorization for operations.
- Large text and narrow windows stay readable, with keyboard access to key actions.
- Errors offer a next step; missing data is not represented as success or zero usage.

Requirements define intended behavior, not evidence that a test was performed.
