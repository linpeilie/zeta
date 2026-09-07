# Conversations and the Timeline

A conversation belongs to one project and one AI assistant and can be continued later. One request and the assistant's work on it make up a turn.

## Read the records

The conversation shows your messages, replies and operations reported by the assistant. Open an operation to inspect its command, files or result. Consecutive operations of the same kind may be grouped together.

If the assistant provides a reasoning summary, you can expand it. After a task, “Changes this turn” shows reported file edits for comparison. Missing details do not prove that no files changed; check the project files too.

Each turn is marked as running, completed, failed or interrupted. New content does not pull you to the bottom while you read earlier messages. Use the new-content prompt to return to the latest reply, or the conversation navigation to jump to a turn.

## Enter a message

Enter sends and Shift + Enter adds a line by default. You can change this in settings.

| Input | Purpose |
| --- | --- |
| `@` | Find a project file by name and reference it |
| `$` | Choose a Skill: a prepared set of task instructions |
| `/` | Open commands such as planning or shortening a long conversation |
| Paste or attach an image | Send a screenshot or other image to the assistant |

These controls appear only when supported. Use the arrow keys to choose a menu item, Enter to confirm, and Esc to close it.

## Model and reasoning options

Choose a model beside the input box. Where available, you can also adjust reasoning effort or use Fast. The interface explains when a change takes effect. It does not change completed turns.

Read any confirmation before proceeding. If saving fails, the previous choice remains and you can retry.

## Cancel a task

Select “Cancel turn” while a task runs. After sending the request, check the turn's status to confirm it has stopped.

**Cancellation does not undo commands or file changes already made.** Restore files using your project's backup or version control tool.

## Edit a message or create a branch

Supporting assistants offer actions such as editing a message, branching and retrying. These keep the original conversation and start another from the chosen point.

A new branch changes conversation history only. Files changed by the earlier task stay as they are.

## Shorten a long conversation

An assistant can consider only a limited amount of conversation at once. `Compact` asks it to summarize existing content to make room for more. Some detail may be lost; restate important requirements in your next message when needed.

Some assistants do this automatically and leave a notice in the conversation.

## Read-only conversation

Check whether the conversation's assistant is disabled under “Settings → Agents”. Enable it and try again. If it remains unavailable, see [Troubleshooting](troubleshooting.md).
