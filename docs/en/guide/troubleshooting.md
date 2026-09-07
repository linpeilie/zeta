# Troubleshooting

Check the symptom below. If it persists, use the reporting instructions at the end.

## Installation and startup

**The system blocks first launch.** Current packages lack a developer signature. Verify the source before following your system's open options. An unidentified-developer warning differs from a damaged-file message or antivirus alert. For the latter two, download again, check the checksum file and keep the warning text for a report.

**Linux has no application entry after installation.** Refresh the application menu or run `zeta` from the extracted folder.

**The window is blank or closes immediately.** Record the system version, Zeta version and steps. If a log was created, inspect today's file under `logs` in the [data folder](data-and-privacy.md#what-zeta-saves).

**Conversation list fails right after install.** Quit Zeta fully, then open it from the Start menu.

**Settings disappear after restart.** Check that Documents is writable, the disk has space and a cleanup tool has not removed `.zeta`. Do not move or remove this folder while Zeta runs.

## Assistant connections

**Not detected.** Check that the assistant is installed and works independently. Fully quit and reopen Zeta after installation, then run detection under “Settings → Agents”. Check the reported program location; multiple installed versions may cause differences.

To check the installed version in a terminal, run the line for your assistant:

```sh
codex --version
grok --version
claude --version
```

**Not signed in or connection failed.** Sign in through the assistant, then test again. If it works in a terminal only, check that Zeta uses the same program, account and settings. Follow the detection page's advice and review [versions](agents.md#versions).

**Empty model list.** Check sign-in and connection before refreshing. A retained older list does not prove that the current connection succeeded; check its status.

**Claude Code sign-in renewal failed.** Sign in again through Claude Code and retry. Turning off quota details does not fix an expired sign-in.

## Conversations and files

**Input is unavailable.** Check whether the assistant is disabled or is carrying out an operation during which sending is unavailable.

**The task is not continuing.** Look for permission or question cards above the input. Otherwise, read the latest error or waiting notice.

**An accepted plan did not start.** Check whether execution permissions still need confirmation or the plan is being revised. See [Approvals and Plans](approvals.md).

**Files stayed changed after cancellation.** Cancelling stops later work, not completed edits. Branching a conversation also does not restore files. Use backups or version control to restore them.

**The assistant did not read the selected file.** Selection supplies a location. Ask explicitly for the file to be read, and check reported operations.

**Scrolling is slow.** Report the approximate conversation length, whether it has large images or code blocks, and whether resizing makes it worse.

## Projects and history

**Some folders are missing.** `.git`, `.dart_tool`, `.idea`, `.vscode`, `build` and `node_modules` are hidden. This list is not currently configurable.

**A project disappeared.** Check whether it moved or was deleted, external drives are connected, and Zeta has read permission. Try opening the project again.

**History will not open.** Check the original assistant and account, and whether its history files still exist. Zeta's cached list cannot recover deleted complete history.

## Notifications

Check “Settings → General → Notifications”, system permissions and Do Not Disturb. Reminders are suppressed while you view the corresponding conversation.

If clicking a notification fails, try reopening the project. A notification cannot recover a deleted conversation.

## Usage

**Numbers differ.** Check date, assistant, model and project filters. Statistics can include terminal tasks. Cancelled tasks count in the ended total but not as successes.

**Some data unavailable.** Only readable history is shown, so results may be incomplete. Missing response times do not enter the average; missing quota is not zero.

**No usage records.** Widen the date range, select all assistants and refresh. History already removed by the assistant cannot be rebuilt by Zeta.

## Report a problem

Use [Issues](https://github.com/linpeilie/zeta/issues/new/choose) to provide your system and version, Zeta version, assistant name and version, reproduction steps and the result.

Attach only relevant log excerpts after masking accounts, private paths, keys and conversation content. Use the private route in the [Security Policy](../../../SECURITY.md) for vulnerabilities.
