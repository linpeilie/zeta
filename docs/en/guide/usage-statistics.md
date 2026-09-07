# Usage Statistics

Open usage from the title bar to see call counts, success rates, usage and response times.

## What the numbers mean

| Metric | Meaning |
| --- | --- |
| Calls | One request and the assistant's work on it count as one call |
| Success rate | The share of ended tasks that completed normally; failed and cancelled tasks are included in the total |
| Token usage | Text units reported by the assistant, roughly small pieces of text; not a word count or a price |
| Average response time | Time from sending a request to receiving the first response, only for tasks with a recorded value |

Running tasks and those with unknown status are excluded from the success rate. The page shows how many tasks have response-time records.

Statistics come from the assistant's local history and may include tasks run from a terminal. Missing data is marked unavailable or unsupported, not replaced with an estimate.

## Filters and details

Choose a date range, assistant and model at the top. Use the project list to focus on a project, and refresh to read data again.

The chart shows changes during the selected period. Below it, review summaries by assistant, model or project, or open the task list for a task's time, model, usage and result.

Task details do not contain conversation bodies or tool output. Open the corresponding conversation for those.

## Plan limits

The quota panel shows plan information, usage percentages and reset times supplied by the assistant. It may use an online query and is separate from local history statistics.

Claude Code's detailed usage requires the [quota-details enhancement](agents.md#claude-code-quota-details). An unreadable value means neither zero usage nor unlimited availability.

Zeta does not calculate your bill. Use the service's bill or account page for actual charges and remaining allowances.

## Incomplete data

Missing, damaged or unreadable history and different filters can explain differences from other tools. “Some data unavailable” means results include only readable records and may not be a complete total.

Check filters and refresh first. See [Data and Privacy](data-and-privacy.md#clear-or-reset-data) before clearing cached statistics.
