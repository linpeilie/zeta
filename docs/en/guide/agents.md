# Connecting AI Assistants

Use “Settings → Agents” to detect and manage assistants. Agent or Provider in the interface refers to a connected AI assistant. Claude Code is also shown as Claude in some places.

## Supported features

Codex, Grok and Claude Code all support new conversations, resuming history, cancellation, permission requests, questions and model selection. Other features differ:

| Feature | Codex | Grok | Claude Code |
| --- | :---: | :---: | :---: |
| Add a message while a task runs | ✓ | — | — |
| Rename conversations | ✓ | ✓ | — |
| Archive or branch | ✓ | — | — |
| Delete the assistant's saved conversation | ✓ | ✓ | — |
| Remove only from Zeta's list | — | — | ✓ |
| Shorten long conversations (Compact) | ✓ | — | ✓ |
| Reference files with `@` | ✓ | ✓ | — |
| Choose Skill task instructions | ✓ | ✓ | — |
| Attach images | ✓ | — | — |
| Plan mode | ✓ | ✓ | ✓ |
| Separate “Accept plan” card | — | ✓ | ✓ |
| Fast option | ✓ | — | — |

Actual choices also depend on the assistant version, model and account. Unsupported controls are hidden. See [Approvals, Questions and Plans](approvals.md).

## Detect and connect

1. Run automatic Agent detection.
2. Select an assistant to check installation, sign-in and version information.
3. Follow any problem-solving advice, then test the connection.

Connection tests do not send a chat message or request a model answer. The assistant may still connect to the internet, check sign-in or update its own files. Read any confirmation shown before testing.

If the assistant works in a terminal but is not found, fully quit and reopen Zeta. If needed, check the program location shown on the management page. A recent installation or multiple installed versions can cause differences.

Read the prompt before disabling an assistant: running tasks may stop. Existing conversations remain readable. Enable the assistant before trying to send again.

## Models

The Models page lists models currently supplied by the assistant and the last update time. Check sign-in and connection if loading fails. The interface identifies older retained lists.

## Configuration

The Configuration page edits the assistant's own settings file and is intended for people familiar with those settings.

Sensitive values are hidden by default. Show the full content before editing. Saving checks the format and outside changes, and backs up the original configuration. If another program changed the file, compare both versions before deciding what to keep.

Follow any restart instruction after saving. Do not post configurations containing passwords or keys in public issue reports.

## Logs

View running logs to filter, search or copy them. Common passwords and keys are masked, but check project paths, filenames and account information before sharing.

## Claude Code quota details

The quota-details enhancement reads more detailed plan usage, such as five-hour and weekly usage. Turning it off keeps conversations, model lists and the plan name available.

Regardless of this switch, Zeta may update Claude Code's existing sign-in information before connecting or sending a new request to keep it signed in. It does not save another credential copy in Zeta's data folder. Follow the sign-in advice if renewal fails. See [Data and Privacy](data-and-privacy.md#assistant-data-and-sign-in).

## Versions

These are compatibility records for this project, not the latest assistant releases:

- Codex: minimum compatible version 0.142.5; branching at a particular historical point requires 0.144.5.
- Grok: the multiple-conversation baseline is 0.2.119.
- Claude Code: the project has checked different features with 2.1.224, 2.1.227 and 2.1.228. This does not establish a minimum version or guarantee all later releases.

Follow the detection page's advice for incompatible versions. For other problems, see [Troubleshooting](troubleshooting.md#assistant-connections).
